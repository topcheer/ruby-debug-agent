require 'json'

module DebugAgent
  SYSTEM_PROMPT = <<~PROMPT
    You are an expert runtime debugging assistant embedded inside a live Ruby application.
    You have access to diagnostic tools that inspect the running process in real-time.

    Your job:
    1. Understand the user's problem or question.
    2. Decide which tools to call to gather diagnostic data.
    3. Analyze the results and explain findings clearly.
    4. Suggest actionable fixes when appropriate.

    Be concise. Use tables and lists when helpful. If something looks abnormal, point it out.
  PROMPT

  class DebugEngine
    attr_reader :tools

    def initialize(config = nil)
      @config = config || Config.from_env
      @llm = LLMClient.new(@config.llm)
      @tools = REGISTRY
      @conversations = {}
    end

    def chat_stream(message, session_id = 'default')
      Enumerator.new do |yielder|
        history = @conversations[session_id] || [{ 'role' => 'system', 'content' => SYSTEM_PROMPT }]
        history << { 'role' => 'user', 'content' => message }
        @conversations[session_id] = history

        tool_schemas = @tools.all_schemas
        rounds = 0

        while rounds <= @config.llm.max_tool_rounds
          rounds += 1

          response = @llm.chat(history, tool_schemas.empty? ? nil : tool_schemas)
          choice = response.dig('choices', 0)
          unless choice
            yielder << ['token', 'No response from LLM.']
            yielder << ['done', nil]
            break
          end

          msg = choice['message']

          if msg['tool_calls']&.any?
            history << msg

            msg['tool_calls'].each do |tc|
              tool_name = tc.dig('function', 'name')
              args = {}
              begin
                args = JSON.parse(tc.dig('function', 'arguments') || '{}')
              rescue JSON::ParserError
              end

              yielder << ['tool_call', { tool: tool_name, args: args }]

              result = @tools.execute(tool_name, args)

              yielder << ['tool_result', { tool: tool_name, result: result }]

              result_str = JSON.generate(result)
              result_str = result_str[0..12000] if result_str.length > 12000

              history << {
                'role' => 'tool',
                'tool_call_id' => tc['id'],
                'content' => result_str
              }
            end

            next
          end

          # Final answer
          content = msg['content'] || ''
          history << { 'role' => 'assistant', 'content' => content }

          yielder << ['token', content] unless content.empty?
          yielder << ['done', nil]
          break
        end

        if rounds > @config.llm.max_tool_rounds
          yielder << ['token', '_Reached maximum tool-call rounds._']
          yielder << ['done', nil]
        end
      end
    end

    def clear_session(session_id = 'default')
      @conversations.delete(session_id)
    end
  end
end
