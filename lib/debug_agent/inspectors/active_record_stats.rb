require 'thread'

module DebugAgent
  # Track ActiveRecord SQL events (sql.active_record) to report query stats
  # and N+1 detection hints. Auto-installs a subscriber when the tool is run.
  @ar_stats = {
    total_queries: 0,
    total_time_ms: 0.0,
    slow_queries: [],
    query_counts: Hash.new(0),
    query_times: Hash.new(0.0),
    slow_threshold_ms: 100
  }
  @ar_lock = Mutex.new
  @ar_tracker_installed = false

  class << self
    attr_reader :ar_stats

    # Subscribe to sql.active_record notifications (idempotent).
    def install_ar_tracker
      return true if @ar_tracker_installed
      return false unless defined?(::ActiveSupport::Notifications)

      ::ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, started, finished, _id, payload|
        DebugAgent.record_ar_query(started, finished, payload)
      end
      @ar_tracker_installed = true
      true
    end

    def record_ar_query(started, finished, payload)
      duration_ms = ((finished - started) * 1000.0)
      sql = payload[:sql].to_s.strip
      return if sql.empty?

      fp = ar_fingerprint(sql)
      name = payload[:name]

      @ar_lock.synchronize do
        s = @ar_stats
        s[:total_queries] += 1
        s[:total_time_ms] += duration_ms
        next unless fp
        s[:query_counts][fp] += 1
        s[:query_times][fp] += duration_ms
        if duration_ms >= s[:slow_threshold_ms] && s[:slow_queries].size < 200
          s[:slow_queries] << {
            sql: sql[0..500],
            name: name,
            duration_ms: duration_ms.round(2),
            timestamp: finished.to_s
          }
        end
      end
    rescue
      nil
    end

    # Normalize SQL into a fingerprint for grouping / N+1 detection.
    def ar_fingerprint(sql)
      sql
        .gsub(/'[^']*'/, '?')
        .gsub(/\b\d+\b/, '?')
        .gsub(/\s+/, ' ')
        .strip[0..200]
    end
  end

  register_tool('get_active_record_query_stats',
                'Query statistics from ActiveRecord: total queries, avg query time, ' \
                'slow queries, and N+1 detection hints (subscribes to sql.active_record)') do
    next { error: 'ActiveRecord is not loaded (activerecord gem not installed)' } unless defined?(::ActiveRecord)

    install_ar_tracker

    snapshot = @ar_lock.synchronize do
      {
        total_queries: @ar_stats[:total_queries],
        total_time_ms: @ar_stats[:total_time_ms].round(2),
        slow_queries: @ar_stats[:slow_queries].dup,
        query_counts: @ar_stats[:query_counts].dup,
        query_times: @ar_stats[:query_times].dup,
        slow_threshold_ms: @ar_stats[:slow_threshold_ms]
      }
    end

    total = snapshot[:total_queries]
    avg = total.zero? ? 0.0 : (snapshot[:total_time_ms] / total)

    # N+1 suspects: the same query fingerprint executed many times.
    n_plus_suspects =
      snapshot[:query_counts]
        .select { |_, count| count >= 5 }
        .sort_by { |_, count| -count }
        .first(10)
        .map do |fp, count|
          time = snapshot[:query_times][fp]
          {
            fingerprint: fp,
            count: count,
            total_time_ms: time.round(2),
            avg_time_ms: (time / count).round(2)
          }
        end

    result = {
      tracker_active: @ar_tracker_installed,
      total_queries: total,
      total_query_time_ms: snapshot[:total_time_ms],
      avg_query_time_ms: avg.round(2),
      slow_query_threshold_ms: snapshot[:slow_threshold_ms],
      slow_query_count: snapshot[:slow_queries].size,
      slow_queries: snapshot[:slow_queries].last(20).reverse,
      n_plus_suspects: n_plus_suspects
    }

    # Best-effort: include query cache info if available.
    if ::ActiveRecord::Base.connection.respond_to?(:query_cache)
      begin
        result[:query_cache_enabled] = ::ActiveRecord::Base.connection.query_cache_enabled
      rescue
        nil
      end
    end

    result
  rescue => e
    { error: e.message }
  end
end
