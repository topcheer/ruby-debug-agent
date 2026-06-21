require 'time'

module DebugAgent
  class ChatSession
    attr_accessor :session_id, :messages, :last_token_usage,
                  :cumulative_prompt_tokens, :cumulative_completion_tokens

    def initialize(session_id)
      @session_id = session_id
      @messages = []
      @created_at = Time.now
      @last_active_at = @created_at
      @last_token_usage = nil
      @cumulative_prompt_tokens = 0
      @cumulative_completion_tokens = 0
    end

    def add_message(msg)
      @messages << msg
      @last_active_at = Time.now
    end

    def replace_messages(msgs)
      @messages = msgs
      @last_active_at = Time.now
    end

    def record_token_usage(usage)
      return unless usage
      @last_token_usage = usage
      @cumulative_prompt_tokens = usage['prompt_tokens'] || 0
      @cumulative_completion_tokens += usage['completion_tokens'] || 0
    end

    def current_context_tokens
      @cumulative_prompt_tokens
    end

    def clear
      @messages = []
      @last_token_usage = nil
      @cumulative_prompt_tokens = 0
      @cumulative_completion_tokens = 0
      @last_active_at = Time.now
    end
  end
end
