module DebugAgent
  class Config
    attr_accessor :enabled, :base_path, :llm

    def initialize
      @enabled = true
      @base_path = '/agent'
      @llm = LLMConfig.new
    end

    def self.from_env
      c = new
      c.enabled = ENV.fetch('DEBUG_AGENT_ENABLED', 'true').downcase == 'true'
      c.base_path = ENV.fetch('DEBUG_AGENT_BASE_PATH', '/agent')
      c.llm = LLMConfig.from_env
      c
    end
  end

  class LLMConfig
    attr_accessor :base_url, :api_key, :model, :temperature, :max_tokens, :max_tool_rounds, :timeout_seconds

    def initialize
      @base_url = 'https://api.openai.com/v1'
      @api_key = ''
      @model = 'gpt-4o'
      @temperature = 0.3
      @max_tokens = 4096
      @max_tool_rounds = 10
      @timeout_seconds = 120
    end

    def self.from_env
      c = new
      c.base_url = ENV.fetch('LLM_BASE_URL', 'https://api.openai.com/v1')
      c.api_key = ENV.fetch('LLM_API_KEY', '')
      c.model = ENV.fetch('LLM_MODEL', 'gpt-4o')
      c.temperature = ENV.fetch('LLM_TEMPERATURE', '0.3').to_f
      c.max_tokens = ENV.fetch('LLM_MAX_TOKENS', '4096').to_i
      c.max_tool_rounds = ENV.fetch('LLM_MAX_TOOL_ROUNDS', '10').to_i
      c.timeout_seconds = ENV.fetch('LLM_TIMEOUT_SECONDS', '120').to_i
      c
    end
  end
end
