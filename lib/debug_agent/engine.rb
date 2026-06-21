require 'json'

module DebugAgent
  # StreamHandler implementation used internally by the engine
  class EngineStreamHandler < StreamHandler
    attr_reader :tool_calls, :usage, :had_error, :content

    def initialize(callback)
      @callback = callback
      @tool_calls = []
      @usage = nil
      @had_error = false
      @content = +''
    end

    def on_content(chunk)
      @content << chunk
      @callback.on_content(chunk)
    end

    def on_complete(tool_calls, finish_reason, usage)
      @tool_calls = tool_calls
      @usage = usage
    end

    def on_error(error)
      @had_error = true
      @callback.on_error("LLM API error: #{error.message}")
    end
  end

  class DebugEngine
    attr_reader :tools, :system_prompt

    def initialize(config = nil)
      @config = config || Config.from_env
      @llm = LLMClient.new(@config.llm)
      @tools = REGISTRY

      @prompt_builder = SystemPromptBuilder.new(@tools)
      @system_prompt = @prompt_builder.build

      @context_compressor = ContextCompressor.new(
        @llm, @config.llm.model, @config.llm.temperature, @config.llm.context_window_tokens
      )

      @sessions = {}
      @mutex = Mutex.new
    end

    def chat(message, session_id = 'default', callback = nil)
      callback ||= ChatCallback.new

      session = get_or_create_session(session_id)
      session.add_message({ 'role' => 'user', 'content' => message })

      run_tool_loop(session, callback)
    end

    def clear_session(session_id = 'default')
      @mutex.synchronize do
        session = @sessions[session_id]
        session&.clear
      end
    end

    private

    def get_or_create_session(session_id)
      @mutex.synchronize do
        @sessions[session_id] ||= ChatSession.new(session_id)
      end
    end

    def run_tool_loop(session, cb)
      max_rounds = @config.llm.max_tool_rounds

      max_rounds.times do |round_num|
        # Context compression
        if round_num > 0 && @context_compressor.needs_compression?(session.current_context_tokens)
          result = @context_compressor.compress(session)
          if result
            cb.on_content("\n\n> [Context auto-compressed: #{result.original_tokens} -> ~#{result.compressed_tokens} tokens (#{result.strategy})]\n\n")
            cb.on_context_compressed(result.original_tokens, result.compressed_tokens, result.removed_rounds)
          end
        end

        messages = [{ 'role' => 'system', 'content' => @system_prompt }] + session.messages
        tool_schemas = @tools.all_schemas

        handler = EngineStreamHandler.new(cb)
        @llm.chat_stream_raw(messages, tool_schemas, 'auto', handler)

        return if handler.had_error

        session.record_token_usage(handler.usage) if handler.usage

        if handler.tool_calls.empty?
          # After tool calls, if LLM returns empty content, prompt it to summarize
          if handler.content.strip.empty? && round_num > 0
            session.add_message({ 'role' => 'assistant', 'content' => '' })
            session.add_message({
              'role' => 'user',
              'content' => 'You called tools but did not provide any analysis. ' \
                'Please summarize the key findings from the tool results above and ' \
                'provide actionable recommendations.'
            })
            next
          end

          # Final answer
          session.add_message({ 'role' => 'assistant', 'content' => handler.content })
          cb.on_complete
          return
        end

        # Execute tool calls
        session.add_message({
          'role' => 'assistant',
          'content' => handler.content,
          'tool_calls' => handler.tool_calls
        })

        handler.tool_calls.each do |tc|
          tool_name = tc['function']['name']
          args = {}
          begin
            args = JSON.parse(tc['function']['arguments'] || '{}')
          rescue JSON::ParserError
          end

          cb.on_tool_start(tool_name, tc['function']['arguments'])

          result = @tools.execute(tool_name, args)
          result_str = JSON.generate(result)
          result_str = result_str[0..12_000] if result_str.length > 12_000

          cb.on_tool_result(tool_name, result_str)
          session.add_message({
            'role' => 'tool',
            'tool_call_id' => tc['id'],
            'content' => result_str
          })
        end
      end

      # Max rounds — force final summary
      final_messages = [{ 'role' => 'system', 'content' => @system_prompt }] + session.messages
      final_messages << {
        'role' => 'system',
        'content' => 'You have reached the maximum number of tool-calling rounds. ' \
          'Based on all the diagnostic data you have gathered so far, ' \
          'provide a comprehensive analysis and actionable recommendations NOW. ' \
          'Do not attempt to call more tools.'
      }

      handler = EngineStreamHandler.new(cb)
      @llm.chat_stream_raw(final_messages, [], 'none', handler)
      cb.on_complete
    end
  end
end
