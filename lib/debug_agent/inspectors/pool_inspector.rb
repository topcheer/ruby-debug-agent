require 'time'

module DebugAgent
  # Register connection pools for deep-dive inspection.
  #
  #   DebugAgent.register_pool(:primary, ActiveRecord::Base.connection_pool)
  @registered_pools = {}
  @pool_stats = {}
  @pool_meta_lock = Mutex.new

  class << self
    attr_reader :registered_pools, :pool_stats

    def register_pool(name, pool)
      pool_name = name.to_s
      @registered_pools[pool_name] = pool
      @pool_meta_lock.synchronize do
        @pool_stats[pool_name] ||= {
          acquire_times: [],
          last_checked_at: nil
        }
      end
      pool
    end
  end

  class << self
    private

    def ar_pool_stats
      return nil unless defined?(::ActiveRecord::Base)

      begin
        pool = ::ActiveRecord::Base.connection_pool
        stats = {}

        # ActiveRecord::ConnectionPool#stats (Rails 5+)
        if pool.respond_to?(:stats)
          stats = pool.stats
        end

        result = {
          size: pool.respond_to?(:size) ? pool.size : nil,
          class: pool.class.name,
          stats: stats
        }

        # Try to get more detail via instance variables if available
        if pool.instance_variable_defined?(:@available)
          available = pool.instance_variable_get(:@available)
          if available.respond_to?(:size)
            result[:available_connections] = available.size
          end
        end

        if pool.instance_variable_defined?(:@connections)
          connections = pool.instance_variable_get(:@connections)
          if connections.is_a?(Array)
            result[:total_connections] = connections.size
            result[:connections] = connections.map do |conn|
              conn_info(conn)
            end
          end
        end

        result
      rescue => e
        { error: "ActiveRecord pool inspection failed: #{e.message}" }
      end
    end

    def conn_info(conn)
      info = { object_id: conn.object_id, class: conn.class.name }
      if conn.respond_to?(:active?)
        begin
          info[:active] = conn.active?
        rescue
          nil
        end
      end
      if conn.respond_to?(:in_use?)
        begin
          info[:in_use] = conn.in_use?
        rescue
          nil
        end
      end
      if conn.respond_to?(:seconds_idle)
        begin
          info[:seconds_idle] = conn.seconds_idle
        rescue
          nil
        end end
      info
    rescue
      { object_id: conn&.object_id, class: conn&.class&.name }
    end

    def pool_details_for(name, pool)
      if defined?(::ActiveRecord::ConnectionAdapters::AbstractAdapter) &&
         pool.is_a?(::ActiveRecord::ConnectionAdapters::AbstractAdapter)
        # Direct adapter, not a pool
        return {
          name: name,
          class: pool.class.name,
          type: 'adapter',
          active: (pool.active? if pool.respond_to?(:active?)),
          in_use: (pool.in_use? if pool.respond_to?(:in_use?)),
          seconds_idle: (pool.seconds_idle if pool.respond_to?(:seconds_idle))
        }
      end

      # ActiveRecord ConnectionPool
      if pool.respond_to?(:stats) || pool.respond_to?(:size)
        stats = {}
        stats[:size] = pool.size if pool.respond_to?(:size)
        stats[:stats] = pool.stats if pool.respond_to?(:stats)

        if pool.instance_variable_defined?(:@connections)
          conns = pool.instance_variable_get(:@connections)
          if conns.is_a?(Array)
            stats[:total_connections] = conns.size
            stats[:connections] = conns.map { |c| conn_info(c) }
            stats[:busy_connections] = conns.count { |c| c.respond_to?(:in_use?) ? c.in_use? : false }
            stats[:idle_connections] = conns.count { |c| c.respond_to?(:in_use?) ? !c.in_use? : true }
            stats[:dead_connections] = conns.count do |c|
              c.respond_to?(:active?) ? !c.active? : false
            rescue
              true
            end
          end
        end

        return { name: name, class: pool.class.name, type: 'active_record_pool' }.merge(stats)
      end

      # Custom pool — best-effort introspection
      info = { name: name, class: pool.class.name, type: 'custom' }
      %i[size available busy idle dead count total active checkout checkin].each do |m|
        if pool.respond_to?(m)
          begin
            val = pool.public_send(m)
            info[m] = val unless val.nil?
          rescue
            nil
          end
        end
      end
      info
    end
  end

  register_tool('get_pool_details',
                'Connection pool deep dive: size, busy, dead, idle connections. ' \
                'Auto-detects ActiveRecord::Base.connection_pool or uses registered pools') do
    pools = []

    # Registered pools
    registered_pools.each do |name, pool|
      pools << pool_details_for(name, pool)
    end

    # Auto-detect ActiveRecord pool if not already registered
    if defined?(::ActiveRecord::Base) && registered_pools.none? { |_, p| p == ::ActiveRecord::Base.connection_pool rescue false }
      begin
        ar = ar_pool_stats
        if ar && !ar[:error]
          pools << ar.merge(name: 'active_record_default', source: 'auto_detected')
        end
      rescue
        nil
      end
    end

    if pools.empty?
      next {
        error: 'No connection pools available. Load ActiveRecord or register a pool ' \
          'with DebugAgent.register_pool(:name, pool).'
      }
    end

    {
      total_pools: pools.size,
      pools: pools
    }
  rescue => e
    { error: e.message }
  end

  register_tool('detect_pool_leaks',
                'Heuristic connection pool leak detection: flags connections checked out ' \
                'for more than 30 seconds (configurable threshold)') do
    threshold_seconds = 30
    leaks = []
    checked_out = []

    all_pools = registered_pools.dup

    # Auto-detect ActiveRecord pool
    if defined?(::ActiveRecord::Base)
      begin
        all_pools['active_record_default'] = ::ActiveRecord::Base.connection_pool
      rescue
        nil
      end
    end

    all_pools.each do |name, pool|
      pool_info = { name: name, connections: [], leak_count: 0 }

      # ActiveRecord ConnectionPool — access connections via instance variable
      if pool.instance_variable_defined?(:@connections)
        conns = pool.instance_variable_get(:@connections)
        if conns.is_a?(Array)
          conns.each do |conn|
            conn_data = conn_info(conn)

            # Check if connection has been checked out for too long
            if conn.respond_to?(:in_use?) && conn.in_use?
              idle_secs = (conn.respond_to?(:seconds_idle) ? conn.seconds_idle : nil)
              conn_data[:status] = 'checked_out'
              conn_data[:idle_seconds] = idle_secs
              checked_out << { pool: name }.merge(conn_data)

              if idle_secs && idle_secs > threshold_seconds
                conn_data[:leak_suspect] = true
                conn_data[:leak_reason] = "Checked out for #{idle_secs}s (threshold: #{threshold_seconds}s)"
                pool_info[:leak_count] += 1
              end
            end

            pool_info[:connections] << conn_data
          end
        end
      end

      leaks << pool_info if pool_info[:connections].any?
    end

    total_leaks = leaks.sum { |p| p[:leak_count] }

    {
      threshold_seconds: threshold_seconds,
      total_leak_suspects: total_leaks,
      pools_inspected: leaks.size,
      checked_out_connections: checked_out.size,
      pools: leaks,
      recommendation: if total_leaks > 0
                        "#{total_leaks} potential connection leak(s) detected. " \
                          "Check for missing connection.release or unclosed transactions."
                      elsif checked_out.any?
                        "#{checked_out.size} connection(s) checked out but within normal threshold."
                      else
                        'No connection leaks detected.'
                      end
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_pool_wait_stats',
                'Connection pool acquisition wait time statistics: how long threads wait ' \
                'to acquire a database connection from the pool') do
    all_pools = registered_pools.dup

    # Auto-detect ActiveRecord pool
    if defined?(::ActiveRecord::Base)
      begin
        all_pools['active_record_default'] = ::ActiveRecord::Base.connection_pool
      rescue
        nil
      end
    end

    pool_stats = all_pools.map do |name, pool|
      stats = { name: name, class: pool.class.name }

      # ActiveRecord connection pool metrics
      if pool.respond_to?(:stats)
        begin
          raw = pool.stats
          stats[:raw_stats] = raw
          stats[:size] = raw[:size] if raw.is_a?(Hash) && raw[:size]
          stats[:busy] = raw[:busy] if raw.is_a?(Hash) && raw[:busy]
          stats[:dead] = raw[:dead] if raw.is_a?(Hash) && raw[:dead]
          stats[:idle] = raw[:idle] if raw.is_a?(Hash) && raw[:idle]
          stats[:waiting] = raw[:waiting] if raw.is_a?(Hash) && raw[:waiting]
        rescue
          nil
        end
      end

      # Size info
      stats[:pool_size] = pool.size if pool.respond_to?(:size)

      # Count threads waiting (approximate: scan for threads blocked on connection checkout)
      waiting_threads = Thread.list.select do |t|
        next false unless t.alive? && t.status == 'sleep'
        bt = begin
          t.backtrace || []
        rescue
          []
        end
        bt.any? { |line| line =~ /connection_pool|with_connection|checkout|acquire/i }
      end
      stats[:threads_waiting_for_connection] = waiting_threads.size
      stats[:waiting_thread_ids] = waiting_threads.map(&:object_id)

      stats
    end

    {
      total_pools: pool_stats.size,
      total_waiting_threads: pool_stats.sum { |p| p[:threads_waiting_for_connection] || 0 },
      pools: pool_stats
    }
  rescue => e
    { error: e.message }
  end
end
