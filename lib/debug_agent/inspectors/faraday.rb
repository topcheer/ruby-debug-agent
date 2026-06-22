module DebugAgent
  # Registry of named Faraday connections so the inspector can introspect them.
  #
  #   DebugAgent.register_faraday(:api, Faraday.new('https://api.example.com'))
  @faraday_connections = {}

  class << self
    attr_reader :faraday_connections

    def register_faraday(name, conn)
      @faraday_connections[name.to_s] = conn
    end

    def faraday_conn_info(name, conn)
      info = { name: name, class: conn.class.name }

      if conn.respond_to?(:url_prefix)
        info[:url] = conn.url_prefix.to_s
        info[:host] = conn.url_prefix.host
        info[:port] = conn.url_prefix.port
        info[:scheme] = conn.url_prefix.scheme
      end

      builder = conn.respond_to?(:builder) ? conn.builder : nil
      if builder
        handlers =
          if builder.respond_to?(:handlers)
            builder.handlers.map { |h| faraday_handler_name(h) }
          else
            []
          end
        info[:middleware] = handlers

        adapter =
          if builder.respond_to?(:adapter)
            faraday_handler_name(builder.adapter)
          end
        info[:adapter] = adapter if adapter
      end

      info[:headers] = conn.headers.to_h if conn.respond_to?(:headers) && conn.headers.respond_to?(:to_h)

      info
    rescue => e
      { name: name, error: e.message }
    end

    def faraday_handler_name(handler)
      return handler.name if handler.respond_to?(:name)
      return handler.class.name if handler.respond_to?(:class)
      handler.to_s
    end
  end

  register_tool('get_faraday_connections',
                'List registered Faraday connections with URL, adapter, and middleware stack ' \
                '(requires faraday gem)') do |name: nil|
    next { error: 'Faraday is not loaded (faraday gem not installed)' } unless defined?(::Faraday)

    conns = faraday_connections
    if conns.empty?
      next {
        message: 'No Faraday connections registered. Call DebugAgent.register_faraday(:name, conn).'
      }
    end

    targets = name ? { name.to_s => conns[name.to_s] } : conns
    targets = targets.reject { |_, c| c.nil? }
    next { error: "No Faraday connection registered under '#{name}'" } if targets.empty?

    list = targets.map do |conn_name, conn|
      faraday_conn_info(conn_name, conn)
    end

    { connections: list }
  rescue => e
    { error: e.message }
  end
end
