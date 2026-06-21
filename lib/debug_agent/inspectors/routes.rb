require 'json'

module DebugAgent
  register_tool('get_routes',
                'Discover Sinatra/Rack routes from the running application') do
    routes = []
    app = DebugAgent.app

    if app.nil?
      return {
        total: 0,
        routes: [],
        message: 'No application registered with DebugAgent. ' \
          'Ensure the middleware is properly installed.'
      }
    end

    app_class = app.is_a?(Class) ? app : app.class

    # Try Sinatra routes
    if app_class.respond_to?(:routes)
      app_class.routes.each do |method, route_list|
        route_list.each do |route|
          pattern = route[0]
          pattern_str = case pattern
                        when Regexp then pattern.source
                        else pattern.to_s
                        end
          routes << {
            method: method.to_s.upcase,
            pattern: pattern_str,
            file: route[1],
            line: route[2]
          }
        end
      end
    end

    # Fallback: check Sinatra::Base if nothing found
    if routes.empty? && defined?(Sinatra) && defined?(Sinatra::Base)
      Sinatra::Base.routes.each do |method, route_list|
        route_list.each do |route|
          pattern = route[0]
          pattern_str = case pattern
                        when Regexp then pattern.source
                        else pattern.to_s
                        end
          routes << {
            method: method.to_s.upcase,
            pattern: pattern_str,
            file: route[1],
            line: route[2]
          }
        end
      end
    end

    {
      total: routes.size,
      routes: routes
    }
  rescue => e
    { error: e.message, total: 0, routes: [] }
  end

  register_tool('get_middleware_stack',
                'List Rack middleware stack from the running application') do
    stack = []
    app = DebugAgent.app

    if app.nil?
      return {
        total: 0,
        middleware: [],
        message: 'No application registered with DebugAgent.'
      }
    end

    app_class = app.is_a?(Class) ? app : app.class

    # Try Sinatra/Rack middleware stack
    if app_class.respond_to?(:middleware)
      app_class.middleware.each_with_index do |mw, i|
        klass = mw[0]
        args = mw[1..-1]
        stack << {
          index: i,
          name: klass.respond_to?(:name) ? klass.name : klass.to_s,
          arguments: args.map { |a| a.is_a?(String) ? a : a.inspect }
        }
      end
    end

    # Also try Sinatra::Base
    if stack.empty? && defined?(Sinatra) && defined?(Sinatra::Base)
      Sinatra::Base.middleware.each_with_index do |mw, i|
        klass = mw[0]
        args = mw[1..-1]
        stack << {
          index: i,
          name: klass.respond_to?(:name) ? klass.name : klass.to_s,
          arguments: args.map { |a| a.is_a?(String) ? a : a.inspect }
        }
      end
    end

    {
      total: stack.size,
      middleware: stack
    }
  rescue => e
    { error: e.message, total: 0, middleware: [] }
  end
end
