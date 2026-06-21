require 'net/http'
require 'uri'
require 'json'

module DebugAgent
  class LLMClient
    def initialize(config)
      @cfg = config
    end

    def chat(messages, tools = nil)
      uri = URI(@cfg.base_url + '/chat/completions')

      body = {
        model: @cfg.model,
        messages: messages,
        temperature: @cfg.temperature,
        max_tokens: @cfg.max_tokens
      }
      body[:tools] = tools if tools && !tools.empty?

      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{@cfg.api_key}"
      request['Content-Type'] = 'application/json'
      request.body = JSON.generate(body)

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https',
                                 read_timeout: @cfg.timeout_seconds) do |http|
        http.request(request)
      end

      raise "LLM API error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end
end
