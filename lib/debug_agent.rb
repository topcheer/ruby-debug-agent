require_relative 'debug_agent/version'
require_relative 'debug_agent/config'
require_relative 'debug_agent/tool_registry'
require_relative 'debug_agent/llm_client'
require_relative 'debug_agent/engine'
require_relative 'debug_agent/middleware'

# Auto-register built-in inspectors
require_relative 'debug_agent/inspectors/runtime'
require_relative 'debug_agent/inspectors/http_tracker'
require_relative 'debug_agent/inspectors/system'

module DebugAgent
  class Error < StandardError; end
end
