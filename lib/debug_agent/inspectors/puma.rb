module DebugAgent
  register_tool('get_puma_stats',
                'Get Puma worker stats: running workers, threads, backlog, requests ' \
                '(uses Puma.stats if Puma is loaded)') do
    unless defined?(::Puma)
      return { error: 'Puma is not loaded (puma gem not installed)' }
    end

    raw =
      if ::Puma.respond_to?(:stats_hash)
        ::Puma.stats_hash
      elsif ::Puma.respond_to?(:stats)
        # Puma.stats returns a JSON string in older versions; parse it.
        s = ::Puma.stats
        s.is_a?(String) ? JSON.parse(s, symbolize_names: true) : s
      else
        return { error: 'Puma is loaded but does not expose Puma.stats' }
      end

    raw = raw.respond_to?(:transform_keys) ? raw : raw

    # Normalize into a structured summary.
    workers = []

    # Clustered mode: raw is { workers: N, booted_workers: N, old_workers: N,
    #                          phase: N, worker_status: [...] }
    # Single mode: raw is { backed_up: N, running: N, pool_capacity: N,
    #                         max_threads: N, requests_count: N }
    if raw.is_a?(Hash) && raw.key?(:worker_status)
      raw[:worker_status].each_with_index do |w, i|
        last_stats = w[:last_status] || {}
        workers << {
          index: i,
          pid: w[:pid],
          index_field: w[:index],
          booted: w[:booted],
          last_checkin: w[:last_checkin],
          running_threads: last_stats[:running],
          pool_capacity: last_stats[:pool_capacity],
          max_threads: last_stats[:max_threads],
          backlog: last_stats[:backed_up],
          requests: last_stats[:requests_count]
        }
      end

      {
        mode: 'cluster',
        configured_workers: raw[:workers],
        booted_workers: raw[:booted_workers],
        old_workers: raw[:old_workers],
        phase: raw[:phase],
        workers: workers,
        total_running_threads: workers.sum { |w| w[:running_threads].to_i },
        total_backlog: workers.sum { |w| w[:backlog].to_i },
        total_requests: workers.sum { |w| w[:requests].to_i }
      }
    elsif raw.is_a?(Hash)
      {
        mode: 'single',
        running_threads: raw[:running],
        pool_capacity: raw[:pool_capacity],
        max_threads: raw[:max_threads],
        backlog: raw[:backed_up],
        requests: raw[:requests_count],
        raw: raw
      }
    else
      { raw: raw }
    end
  rescue => e
    { error: e.message }
  end
end
