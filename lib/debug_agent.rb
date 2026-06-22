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
require_relative 'debug_agent/inspectors/core_ext'
require_relative 'debug_agent/inspectors/redis'
require_relative 'debug_agent/inspectors/rails'
require_relative 'debug_agent/inspectors/sidekiq'
require_relative 'debug_agent/inspectors/puma'
require_relative 'debug_agent/inspectors/logging'
require_relative 'debug_agent/inspectors/cache'
require_relative 'debug_agent/inspectors/http_client'
require_relative 'debug_agent/inspectors/metrics'
require_relative 'debug_agent/inspectors/active_record_stats'
require_relative 'debug_agent/inspectors/faraday'
require_relative 'debug_agent/inspectors/concurrent'
require_relative 'debug_agent/inspectors/security'
require_relative 'debug_agent/inspectors/health'
require_relative 'debug_agent/inspectors/scheduler'
require_relative 'debug_agent/inspectors/error_tracking'
require_relative 'debug_agent/inspectors/websocket'

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
