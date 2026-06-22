module DebugAgent
  # Registry for Redis clients (redis-rb). Applications register their
  # Redis / connection-pool objects so the inspector can introspect them.
  #
  #   DebugAgent.register_redis_client(:cache, Redis.new(url: ENV['REDIS_URL']))
  @redis_clients = {}

  class << self
    attr_reader :redis_clients

    def register_redis_client(name, client)
      @redis_clients[name.to_s] = client
    end
  end

  # Resolve a registered Redis client. Accepts a bare Redis object or a
  # ConnectionPool (redis-rb ships ConnectionPool support). We yield a
  # usable connection object to the block.
  def self.with_redis(name = nil)
    name, client = if name
      [name.to_s, redis_clients[name.to_s]]
    else
      redis_clients.first
    end

    return [nil, nil] unless client

    [name, client]
  end

  register_tool('get_redis_pool_stats',
                'Get Redis connection pool stats: registered clients, pool size, ' \
                'available/in-use connections, host, port, db') do |name: nil|
    return { error: 'Redis is not loaded (redis gem not installed)' } unless defined?(::Redis)
    return { error: 'No Redis clients registered. Call DebugAgent.register_redis_client(:name, client).' } if redis_clients.empty?

    targets = name ? { name.to_s => redis_clients[name.to_s] } : redis_clients
    targets = targets.reject { |_, c| c.nil? }
    return { error: "No Redis client registered under '#{name}'" } if targets.empty?

    stats = targets.map do |client_name, client|
      begin
        info = {}

        # ConnectionPool vs bare Redis
        pool = nil
        redis_conn = nil

        if defined?(::ConnectionPool) && client.is_a?(::ConnectionPool)
          pool = client
          client.with { |c| redis_conn = c }
        else
          redis_conn = client
        end

        # Basic server connection details
        info[:client_name] = client_name
        info[:type] = pool ? 'connection_pool' : 'redis'

        if redis_conn.respond_to?(:connection)
          conn = redis_conn.connection rescue {}
          info[:host] = conn[:host]
          info[:port] = conn[:port]
          info[:db]   = conn[:db]
        end

        if pool
          # ConnectionPool does not expose live counters publicly; report
          # configured size. Available/in-use are best-effort via instance vars.
          info[:pool_configured_size] = pool.instance_variable_get(:@size)
          info[:pool_available] = pool.instance_variable_get(:@available)&.length
          info[:pool_in_use] = info[:pool_configured_size].to_i - info[:pool_available].to_i
        else
          info[:pool_configured_size] = 1
          info[:pool_available] = 1
          info[:pool_in_use] = 0
        end

        # Ping to confirm reachability
        info[:connected] = begin
          redis_conn.ping == 'PONG'
        rescue => e
          info[:ping_error] = e.message
          false
        end

        info
      rescue => e
        { client_name: client_name, error: e.message }
      end
    end

    { clients: stats }
  rescue => e
    { error: e.message }
  end

  register_tool('get_redis_info',
                'Execute Redis INFO command and parse key sections ' \
                '(Server, Clients, Memory, Stats, Keyspace)') do |name: nil|
    return { error: 'Redis is not loaded (redis gem not installed)' } unless defined?(::Redis)

    _name, client = DebugAgent.with_redis(name)
    return { error: 'No Redis clients registered. Call DebugAgent.register_redis_client(:name, client).' } unless client

    redis_conn =
      if defined?(::ConnectionPool) && client.is_a?(::ConnectionPool)
        client.with { |c| c }
      else
        client
      end

    raw = redis_conn.info
    sections = {}

    # Group known INFO keys into sections
    section_keys = {
      'Server'  => %w[redis_version redis_mode os arch_bits tcp_port uptime_in_seconds uptime_in_days],
      'Clients' => %w[connected_clients blocked_clients tracking_clients],
      'Memory'  => %w[used_memory used_memory_human used_memory_peak used_memory_peak_human used_memory_rss mem_fragmentation_ratio maxmemory maxmemory_human],
      'Stats'   => %w[total_connections_received total_commands_processed instantaneous_ops_per_sec keyspace_hits keyspace_misses expired_keys evicted_keys pubsub_channels pubsub_patterns],
      'Persistence' => %w[rdb_last_bgsave_status rdb_changes_since_last_save aof_enabled]
    }

    section_keys.each do |section, keys|
      sections[section] = keys.each_with_object({}) do |k, h|
        h[k] = raw[k] if raw.key?(k)
      end
    end

    # Keyspace section looks like "db0:keys=10,expires=0,avg_ttl=0"
    keyspace = {}
    raw.each do |k, v|
      next unless k =~ /^db\d+$/
      parsed = v.split(',').each_with_object({}) do |pair, h|
        key, val = pair.split('=')
        h[key] = val
      end
      keyspace[k] = parsed
    end
    sections['Keyspace'] = keyspace unless keyspace.empty?

    { sections: sections, raw_keys: raw.size }
  rescue => e
    { error: e.message }
  end

  register_tool('get_redis_latency',
                'Measure Redis PING latency over 10 samples (min/avg/max in ms)') do |name: nil, samples: 10|
    return { error: 'Redis is not loaded (redis gem not installed)' } unless defined?(::Redis)

    _name, client = DebugAgent.with_redis(name)
    return { error: 'No Redis clients registered. Call DebugAgent.register_redis_client(:name, client).' } unless client

    samples = samples.to_i
    samples = 10 if samples <= 0

    redis_conn =
      if defined?(::ConnectionPool) && client.is_a?(::ConnectionPool)
        client.with { |c| c }
      else
        client
      end

    latencies = []
    samples.times do
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      redis_conn.ping
      finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      latencies << ((finish - start) * 1000.0)
    end

    {
      samples: latencies.size,
      min_ms: latencies.min.round(3),
      avg_ms: (latencies.sum / latencies.size).round(3),
      max_ms: latencies.max.round(3),
      all_ms: latencies.map { |l| l.round(3) }
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_redis_db_size',
                'Execute Redis DBSIZE command (number of keys in current db)') do |name: nil|
    return { error: 'Redis is not loaded (redis gem not installed)' } unless defined?(::Redis)

    _name, client = DebugAgent.with_redis(name)
    return { error: 'No Redis clients registered. Call DebugAgent.register_redis_client(:name, client).' } unless client

    redis_conn =
      if defined?(::ConnectionPool) && client.is_a?(::ConnectionPool)
        client.with { |c| c }
      else
        client
      end

    {
      db_size: redis_conn.dbsize,
      client: _name
    }
  rescue => e
    { error: e.message }
  end
end
