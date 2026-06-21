module DebugAgent
  LLMConfig = Struct.new(
    :base_url, :api_key, :model, :temperature, :max_tokens,
    :max_tool_rounds, :timeout_seconds, :max_retries,
    :retry_base_delay_ms, :retry_max_delay_ms, :context_window_tokens,
    keyword_init: true
  ) do
    def defaults!
      self.base_url            ||= ENV.fetch('LLM_BASE_URL', 'https://open.bigmodel.cn/api/coding/paas/v4')
      self.api_key             ||= ENV.fetch('LLM_API_KEY', ENV.fetch('OPENAI_API_KEY', ''))
      self.model               ||= ENV.fetch('LLM_MODEL', 'glm-5.2')
      self.temperature         ||= 0.3
      self.max_tokens          ||= 4096
      self.max_tool_rounds     ||= 25
      self.timeout_seconds     ||= 120
      self.max_retries         ||= 3
      self.retry_base_delay_ms ||= 1000
      self.retry_max_delay_ms  ||= 30000
      self.context_window_tokens ||= 100_000
      self
    end
  end

  Config = Struct.new(:enabled, :base_path, :llm, keyword_init: true) do
    def self.from_env
      llm = LLMConfig.new.defaults!
      new(
        enabled: ENV.fetch('DEBUG_AGENT_ENABLED', 'true') == 'true',
        base_path: ENV.fetch('DEBUG_AGENT_BASE_PATH', '/agent'),
        llm: llm
      )
    end
  end
end
