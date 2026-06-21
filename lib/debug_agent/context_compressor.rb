require 'json'

module DebugAgent
  CompressionResult = Struct.new(:original_tokens, :compressed_tokens, :removed_rounds, :strategy, keyword_init: true)

  class ContextCompressor
    def initialize(llm, model, temperature, max_context_tokens, recent_rounds_to_keep = 3)
      @llm = llm
      @model = model
      @temperature = temperature
      @max_context_tokens = max_context_tokens
      @recent_rounds_to_keep = recent_rounds_to_keep
    end

    # Trigger compression when token usage exceeds 75% of context window
    def needs_compression?(current_tokens)
      current_tokens > (@max_context_tokens * 0.75).to_i
    end

    def compress(session)
      original_tokens = session.current_context_tokens
      return nil unless needs_compression?(original_tokens)

      rounds = identify_rounds(session.messages)

      keep_count = [@recent_rounds_to_keep, rounds.size - 1].min
      return nil if keep_count < 1

      summarize_count = rounds.size - keep_count

      to_summarize = rounds.first(summarize_count).flatten
      to_keep = rounds.drop(summarize_count).flatten

      begin
        summary = summarize_with_llm(to_summarize)
      rescue StandardError => e
        summary = fallback_truncate(to_summarize)
      end

      compressed = [
        { 'role' => 'system', 'content' => "[Previous conversation summary — #{summarize_count} rounds compressed]\n\n#{summary}" }
      ] + to_keep

      compressed_tokens = estimate_tokens(compressed)
      session.replace_messages(compressed)

      CompressionResult.new(
        original_tokens: original_tokens,
        compressed_tokens: compressed_tokens,
        removed_rounds: summarize_count,
        strategy: "LLM summarized #{summarize_count} rounds"
      )
    end

    private

    def summarize_with_llm(old_messages)
      conversation_text = ''
      old_messages.each do |msg|
        case msg['role']
        when 'user'
          conversation_text << "[User] #{msg['content']}\n\n"
        when 'assistant'
          conversation_text << "[Assistant] #{msg['content']}\n\n" if msg['content']
          (msg['tool_calls'] || []).each do |tc|
            fn = tc['function'] || {}
            conversation_text << "[Tool Call] #{fn['name']}(#{fn['arguments']})\n\n"
          end
        when 'tool'
          content = msg['content'].to_s
          content = content[0..2000] + '...[truncated]' if content.length > 2000
          conversation_text << "[Tool Result] #{content}\n\n"
        end
      end

      prompt = <<~PROMPT
        You are a conversation summarizer for a Ruby debugging assistant.
        Summarize the KEY diagnostic findings from the conversation below concisely.

        Focus on preserving:
        - Problems investigated and their root causes (if found)
        - Key tool results: actual numbers, statuses, error messages, configuration values
        - Recommendations or fixes already suggested
        - Any unresolved issues or follow-up actions pending

        Rules:
        - Be concise but preserve ALL important data points
        - Use bullet points
        - Do NOT include full JSON dumps
        - Keep it under 600 words
      PROMPT

      response = @llm.chat(
        [
          { 'role' => 'system', 'content' => prompt },
          { 'role' => 'user', 'content' => "Conversation to summarize:\n\n#{conversation_text}" }
        ],
        nil
      )
      response.dig('choices', 0, 'message', 'content') || '(summary unavailable)'
    end

    def fallback_truncate(messages)
      sb = +"Previous conversation summary (fallback):\n\n"
      messages.each do |msg|
        if msg['role'] == 'user' && msg['content']
          q = msg['content'].length > 100 ? msg['content'][0..99] + '...' : msg['content']
          sb << "- User asked: #{q}\n"
        end
        if msg['role'] == 'assistant' && msg['tool_calls']
          msg['tool_calls'].each { |tc| sb << "- Called tool: #{tc.dig('function', 'name')}\n" }
        end
      end
      sb
    end

    def identify_rounds(messages)
      rounds = []
      current = []
      has_assistant = false

      messages.each do |msg|
        case msg['role']
        when 'user'
          if current.any?
            rounds << current
            current = []
            has_assistant = false
          end
          current << msg
        when 'assistant'
          if has_assistant
            rounds << current
            current = []
            has_assistant = false
          end
          current << msg
          has_assistant = true
        else
          current << msg
        end
      end
      rounds << current if current.any?
      rounds
    end

    def estimate_tokens(messages)
      chars = 0
      messages.each do |msg|
        chars += (msg['content'] || '').length
        (msg['tool_calls'] || []).each do |tc|
          fn = tc['function'] || {}
          chars += (fn['name'] || '').length + (fn['arguments'] || '').length
        end
      end
      chars / 4
    end
  end
end
