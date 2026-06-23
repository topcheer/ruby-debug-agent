require 'json'
require_relative 'chat_page'

module DebugAgent
  # SSE callback that collects events for both buffered and streaming modes.
  # In streaming mode, events are yielded in real-time via an Enumerator.
  class SseCallback < ChatCallback
    def initialize
      @events = []
      @queue = Queue.new
      @done = false
    end

    def events
      @events
    end

    def on_content(chunk)
      @events << ['content', JSON.generate(chunk)]
      @queue << ['content', JSON.generate(chunk)]
    end

    def on_tool_start(tool_name, args)
      @events << ['tool_start', tool_name]
      @queue << ['tool_start', tool_name]
    end

    def on_tool_result(tool_name, result)
      @events << ['tool_result', "#{tool_name}: #{result}"]
      @queue << ['tool_result', "#{tool_name}: #{result}"]
    end

    def on_complete
      @events << ['done', '']
      @queue << ['done', '']
      @done = true
      @queue.close
    end

    def on_error(message)
      @events << ['error', message]
      @queue << ['error', message]
      @done = true
      @queue.close
    end

    def on_context_compressed(original, compressed, removed_rounds)
      info = JSON.generate({ originalTokens: original, compressedTokens: compressed, removedRounds: removed_rounds })
      @events << ['context_compressed', info]
      @queue << ['context_compressed', info]
    end

    # Real-time streaming Enumerator: yields SSE-formatted lines as events arrive.
    def streaming_enum
      Enumerator.new do |yielder|
        while (item = @queue.pop)
          event_type, data = item
          yielder << "event: #{event_type}\ndata: #{data}\n\n"
        end
      end
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
    CORS_HEADERS = {
      'Access-Control-Allow-Origin' => '*',
      'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers' => 'Content-Type, Authorization',
    }.freeze

    def self.call(env, app, engine, config)
      path = env['PATH_INFO']
      method = env['REQUEST_METHOD']
      base = config.base_path

      # CORS preflight for all agent routes
      if path.start_with?(base) && method == 'OPTIONS'
        return [204, CORS_HEADERS.merge('Content-Length' => '0'), []]
      end

      # Chat UI
      if path == base || path == "#{base}/"
        if method == 'GET'
          html = ChatPage.render(base)
          return [200, { 'Content-Type' => 'text/html; charset=utf-8' }.merge(CORS_HEADERS), [html]]
        end
      end

      # SSE streaming chat — real-time streaming via Rack response body
      if path == "#{base}/api/chat" && method == 'POST'
        body = JSON.parse(env['rack.input'].read)
        message = body['message'] || ''
        session_id = body['sessionId'] || "session-#{Time.now.to_i}"

        cb = SseCallback.new

        # Run engine in a background thread for real-time streaming
        Thread.new do
          begin
            engine.chat(message, session_id, cb)
          rescue => e
            cb.on_error("Internal error: #{e.message}")
          end
        end

        # Return a streaming response body (Rack 2+ / Rack 3 compatible)
        streaming_body = cb.streaming_enum

        return [200, {
          'Content-Type' => 'text/event-stream',
          'Cache-Control' => 'no-cache',
          'Connection' => 'keep-alive',
        }.merge(CORS_HEADERS), streaming_body]
      end

      # Clear conversation
      if path == "#{base}/api/clear" && method == 'POST'
        body = JSON.parse(env['rack.input'].read)
        session_id = body['sessionId'] || ''
        engine.clear_session(session_id) if session_id && !session_id.empty?
        return [200, { 'Content-Type' => 'application/json' }.merge(CORS_HEADERS), [JSON.generate({ status: 'cleared' })]]
      end

      # Health check
      if path == "#{base}/api/health" && method == 'GET'
        return [200, { 'Content-Type' => 'application/json' }.merge(CORS_HEADERS), [JSON.generate({ status: 'ok', agent: 'ruby-debug-agent' })]]
      end

      # List tools
      if path == "#{base}/api/tools" && method == 'GET'
        return [200, { 'Content-Type' => 'application/json' }.merge(CORS_HEADERS), [JSON.generate({ tools: engine.tools.all_schemas })]]
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
