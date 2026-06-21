require 'net/http'
require 'uri'
require 'json'
require 'timeout'

module DebugAgent
  # Stream callback interface (engine implements this)
  class StreamHandler
    def on_content(chunk); end
    def on_complete(tool_calls, finish_reason, usage); end
    def on_error(error); end
  end

  # Chat callback interface (engine -> UI)
  class ChatCallback
    def on_content(chunk); end
    def on_tool_start(tool_name, args); end
    def on_tool_result(tool_name, result); end
    def on_complete; end
    def on_error(message); end
    def on_context_compressed(original, compressed, removed_rounds); end
  end

  class LLMClient
    def initialize(config)
      @cfg = config
    end

    # ==================== Non-Streaming ====================

    def chat(messages, tools = nil)
      body = {
        'model' => @cfg.model,
        'messages' => messages,
        'temperature' => 0,
        'max_tokens' => 1024
      }
      body['tools'] = tools if tools

      post_with_retry('/chat/completions', body)
    end

    # ==================== Streaming ====================

    def chat_stream_raw(messages, tools, tool_choice, handler)
      body = {
        'model' => @cfg.model,
        'messages' => messages,
        'temperature' => @cfg.temperature,
        'max_tokens' => @cfg.max_tokens,
        'stream' => true,
        'stream_options' => { 'include_usage' => true }
      }
      body['tools'] = tools if tools && tools.any?
      body['tool_choice'] = tool_choice if tool_choice

      max_retries = @cfg.max_retries
      last_error = nil

      (0..max_retries).each do |attempt|
        begin
          stream_request('/chat/completions', body, handler)
          return
        rescue RetriableError => e
          last_error = e
          if attempt < max_retries
            delay = calculate_delay(attempt)
            sleep(delay / 1000.0)
            next
          end
          handler.on_error(e)
          return
        rescue StandardError => e
          handler.on_error(e)
          return
        end
      end

      handler.on_error(StandardError.new("Exhausted retries: #{last_error&.message}"))
    end

    # ==================== Stream Processing ====================

    def stream_request(path, body, handler)
      uri = URI(@cfg.base_url + path)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = @cfg.timeout_seconds

      request = Net::HTTP::Post.new(uri.path)
      request['Authorization'] = "Bearer #{@cfg.api_key}"
      request['Content-Type'] = 'application/json'
      request.body = JSON.generate(body)

      response = http.request(request)

      if response.code.to_i >= 400
        raise RetriableError.new(response.code.to_i, "HTTP #{response.code}: #{response.body}")
      end

      tool_call_map = {}
      finish_reason = nil
      usage = nil

      response.read_body do |chunk|
        chunk.split("\n").each do |line|
          next unless line.start_with?('data: ')

          data_str = line[6..]
          next if data_str.strip == '[DONE]'

          begin
            parsed = JSON.parse(data_str)
          rescue JSON::ParserError
            next
          end

          if parsed['usage'] && parsed['usage']['prompt_tokens']
            usage = parsed['usage']
          end

          choices = parsed['choices'] || []
          next if choices.empty?

          choice = choices[0]
          delta = choice['delta'] || {}

          if delta['content'] && !delta['content'].empty?
            handler.on_content(delta['content'])
          end

          if delta['tool_calls']
            delta['tool_calls'].each do |tc|
              idx = tc['index'] || 0
              tool_call_map[idx] ||= { 'id' => '', 'type' => 'function', 'function' => { 'name' => '', 'arguments' => '' } }
              entry = tool_call_map[idx]
              entry['id'] = tc['id'] if tc['id']
              entry['type'] = tc['type'] if tc['type']
              fn = tc['function'] || {}
              entry['function']['name'] += fn['name'] if fn['name']
              entry['function']['arguments'] += fn['arguments'] if fn['arguments']
            end
          end

          finish_reason = choice['finish_reason'] if choice['finish_reason']
        end
      end

      tool_calls = tool_call_map.keys.sort.map { |k| tool_call_map[k] }.select { |tc| tc['function']['name'] && !tc['function']['name'].empty? }

      handler.on_complete(tool_calls, finish_reason, usage)
    end

    # ==================== Non-Streaming POST with retry ====================

    def post_with_retry(path, body)
      max_retries = @cfg.max_retries
      last_error = nil

      (0..max_retries).each do |attempt|
        begin
          return post(path, body)
        rescue RetriableError => e
          last_error = e
          if attempt < max_retries
            delay = calculate_delay(attempt)
            sleep(delay / 1000.0)
            next
          end
          raise
        rescue StandardError => e
          raise
        end
      end

      raise last_error
    end

    def post(path, body)
      uri = URI(@cfg.base_url + path)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = @cfg.timeout_seconds

      request = Net::HTTP::Post.new(uri.path)
      request['Authorization'] = "Bearer #{@cfg.api_key}"
      request['Content-Type'] = 'application/json'
      request.body = JSON.generate(body)

      response = http.request(request)

      if response.code.to_i >= 400
        raise RetriableError.new(response.code.to_i, "HTTP #{response.code}: #{response.body}")
      end

      JSON.parse(response.body)
    end

    # ==================== Helpers ====================

    def calculate_delay(attempt)
      base = @cfg.retry_base_delay_ms * (2 ** attempt)
      jitter = rand(base / 2 + 1)
      delay = base + jitter
      [delay, @cfg.retry_max_delay_ms].min
    end
  end

  class RetriableError < StandardError
    attr_reader :status_code

    def initialize(status_code, message)
      super(message)
      @status_code = status_code
    end

    def retriable?
      [429, 500, 502, 503, 504].include?(@status_code)
    end
  end
end
