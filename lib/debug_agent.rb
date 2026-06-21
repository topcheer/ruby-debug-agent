require_relative 'debug_agent/version'
require_relative 'debug_agent/config'
require_relative 'debug_agent/tool_registry'
require_relative 'debug_agent/llm_client'
require_relative 'debug_agent/chat_session'
require_relative 'debug_agent/system_prompt_builder'
require_relative 'debug_agent/context_compressor'
require_relative 'debug_agent/engine'
require_relative 'debug_agent/chat_page'
require_relative 'debug_agent/middleware'

# Auto-register built-in inspectors
require_relative 'debug_agent/inspectors/runtime'
require_relative 'debug_agent/inspectors/http_tracker'
require_relative 'debug_agent/inspectors/system'
require_relative 'debug_agent/inspectors/gc'
require_relative 'debug_agent/inspectors/object_space'
require_relative 'debug_agent/inspectors/threads'
require_relative 'debug_agent/inspectors/routes'
require_relative 'debug_agent/inspectors/process_info'

module DebugAgent
  class Error < StandardError; end

  # Process start time for uptime tracking
  PROCESS_START_TIME = Time.now

  # Reference to the wrapped Rack/Sinatra app for route/middleware inspection
  @app = nil

  class << self
    attr_accessor :app
  end
end
