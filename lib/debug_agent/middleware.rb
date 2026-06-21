require 'json'
require_relative 'chat_page'

module DebugAgent
  # SSE callback that bridges engine to SSE response lines
  class SseCallback < ChatCallback
    def initialize
      @events = []
    end

    def events
      @events
    end

    def on_content(chunk)
      @events << ['content', JSON.generate(chunk)]
    end

    def on_tool_start(tool_name, args)
      @events << ['tool_start', tool_name]
    end

    def on_tool_result(tool_name, result)
      @events << ['tool_result', "#{tool_name}: #{result}"]
    end

    def on_complete
      @events << ['done', '']
    end

    def on_error(message)
      @events << ['error', message]
    end

    def on_context_compressed(original, compressed, removed_rounds)
      info = JSON.generate({ originalTokens: original, compressedTokens: compressed, removedRounds: removed_rounds })
      @events << ['context_compressed', info]
    end
  end

  # Rack-compatible middleware class (use with Sinatra: `use DebugAgent::RackMiddleware`)
  class RackMiddleware
    def initialize(app, config = nil)
      @app = app
      @config = config || Config.from_env
      @engine = DebugEngine.new(@config)
      DebugAgent.app = app
    end

    def call(env)
      MiddlewareCore.call(env, @app, @engine, @config)
    end
  end

  module Middleware
    # Create a lambda-based middleware (for non-Sinatra Rack apps)
    def self.new(app = nil, config = nil)
      config_obj = config || Config.from_env
      engine = DebugEngine.new(config_obj)
      DebugAgent.app = app

      lambda do |env|
        MiddlewareCore.call(env, app, engine, config_obj)
      end
    end
  end

  # Shared routing logic used by both RackMiddleware class and Middleware lambda
  module MiddlewareCore
    def self.call(env, app, engine, config)
      path = env['PATH_INFO']
      method = env['REQUEST_METHOD']
      base = config.base_path

      # Chat UI
      if path == base || path == "#{base}/"
        if method == 'GET'
          html = ChatPage.render(base)
          return [200, { 'Content-Type' => 'text/html; charset=utf-8' }, [html]]
        end
      end

      # SSE streaming chat
      if path == "#{base}/api/chat" && method == 'POST'
        body = JSON.parse(env['rack.input'].read)
        message = body['message'] || ''
        session_id = body['sessionId'] || "session-#{Time.now.to_i}"

        cb = SseCallback.new
        engine.chat(message, session_id, cb)

        stream = cb.events.map { |event_type, data| "event: #{event_type}\ndata: #{data}\n\n" }.join

        return [200, {
          'Content-Type' => 'text/event-stream',
          'Cache-Control' => 'no-cache',
          'Connection' => 'keep-alive'
        }, [stream]]
      end

      # Clear conversation
      if path == "#{base}/api/clear" && method == 'POST'
        body = JSON.parse(env['rack.input'].read)
        session_id = body['sessionId'] || ''
        engine.clear_session(session_id) if session_id && !session_id.empty?
        return [200, { 'Content-Type' => 'application/json' }, [JSON.generate({ status: 'cleared' })]]
      end

      # Health check
      if path == "#{base}/api/health" && method == 'GET'
        return [200, { 'Content-Type' => 'application/json' }, [JSON.generate({ status: 'ok', agent: 'ruby-debug-agent' })]]
      end

      # List tools
      if path == "#{base}/api/tools" && method == 'GET'
        return [200, { 'Content-Type' => 'application/json' }, [JSON.generate({ tools: engine.tools.all_schemas })]]
      end

      # Pass through to the wrapped app
      if app
        app.call(env)
      else
        [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
      end
    end
  end
end
