require 'objspace'

module DebugAgent
  # Snapshot & Diff inspector. Collects metrics across all inspectors at a
  # point in time and allows comparing snapshots to detect changes.
  @metric_snapshots = {}
  @metric_snapshot_counter = 0

  class << self
    attr_reader :metric_snapshots
  end

  register_tool('take_snapshot',
                'Take a cross-inspector snapshot: thread count, fiber count, memory (RSS), ' \
                'GC stats, object count, DB pool stats, cache stats, error count. Returns snapshot ID.') do
    gc = GC.stat
    obj_counts = ObjectSpace.count_objects
    rss = `ps -o rss= -p #{Process.pid}`.to_i

    metrics = {
      taken_at: Time.now,
      threads: Thread.list.size,
      alive_threads: Thread.list.count(&:alive?),
      fiber_count: Fiber.respond_to?(:list) ? Fiber.list.size : count_fibers,
      rss_mb: (rss / 1024.0).round(2),
      gc: {
        count: gc[:count],
        major_gc_count: gc[:major_gc_count],
        minor_gc_count: gc[:minor_gc_count],
        heap_live_slots: gc[:heap_live_slots],
        heap_free_slots: gc[:heap_free_slots],
        total_allocated_objects: gc[:total_allocated_objects],
        total_freed_objects: gc[:total_freed_objects],
        old_objects: gc[:old_objects]
      },
      objects: {
        total: obj_counts[:TOTAL] || obj_counts.values.sum,
        free_slots: obj_counts[:FREE] || 0,
        t_string: obj_counts[:T_STRING] || 0,
        t_array: obj_counts[:T_ARRAY] || 0,
        t_hash: obj_counts[:T_HASH] || 0,
        t_object: obj_counts[:T_OBJECT] || 0,
        t_data: obj_counts[:T_DATA] || 0
      },
      db_pool: gather_db_pool_stats,
      cache: gather_cache_stats,
      error_count: gather_error_count
    }

    @metric_snapshot_counter += 1
    snapshot_id = "snap-#{@metric_snapshot_counter}"

    # Enforce max 100 snapshots to prevent unbounded growth
    if @metric_snapshots.size >= 100
      oldest_key = @metric_snapshots.keys.min_by { |k| k[/\d+/].to_i }
      @metric_snapshots.delete(oldest_key)
    end
    @metric_snapshots[snapshot_id] = metrics

    {
      snapshot_id: snapshot_id,
      taken_at: metrics[:taken_at].iso8601,
      summary: {
        threads: metrics[:threads],
        fibers: metrics[:fiber_count],
        rss_mb: metrics[:rss_mb],
        total_objects: metrics[:objects][:total],
        gc_count: metrics[:gc][:count],
        live_slots: metrics[:gc][:heap_live_slots]
      }
    }
  rescue => e
    { error: e.message }
  end

  register_tool('compare_snapshots',
                'Compare two cross-inspector snapshots. Returns all changed values ' \
                'with deltas.',
                snapshot_a: { type: 'string', description: 'First snapshot ID', required: true },
                snapshot_b: { type: 'string', description: 'Second snapshot ID', required: true }) do |snapshot_a:, snapshot_b:|
    snap_a = @metric_snapshots[snapshot_a.to_s]
    snap_b = @metric_snapshots[snapshot_b.to_s]

    next { error: "Snapshot '#{snapshot_a}' not found. Available: #{@metric_snapshots.keys.join(', ')}" } unless snap_a
    next { error: "Snapshot '#{snapshot_b}' not found. Available: #{@metric_snapshots.keys.join(', ')}" } unless snap_b

    changes = compute_snapshot_diff(snap_a, snap_b, '')

    {
      snapshot_a: snapshot_a,
      snapshot_b: snapshot_b,
      time_between_seconds: (snap_b[:taken_at] - snap_a[:taken_at]).round(2),
      changes: changes
    }
  rescue => e
    { error: e.message }
  end

  register_tool('list_snapshots',
                'List all stored cross-inspector snapshots') do
    if @metric_snapshots.empty?
      next { message: 'No snapshots taken yet. Call take_snapshot first.', count: 0, snapshots: [] }
    end

    {
      count: @metric_snapshots.size,
      snapshots: @metric_snapshots.map do |id, snap|
        {
          snapshot_id: id,
          taken_at: snap[:taken_at].iso8601,
          threads: snap[:threads],
          rss_mb: snap[:rss_mb],
          total_objects: snap[:objects][:total],
          gc_count: snap[:gc][:count]
        }
      end
    }
  rescue => e
    { error: e.message }
  end

  # --- Helpers ---

  class << self
    private

    def count_fibers
      # Best-effort fiber count via ObjectSpace
      count = 0
      ObjectSpace.each_object(Fiber) { count += 1 }
      count
    rescue
      0
    end

    def gather_db_pool_stats
      return nil unless defined?(::ActiveRecord::Base)

      begin
        pool = ::ActiveRecord::Base.connection_pool
        stats = pool.respond_to?(:stats) ? pool.stats : {}
        {
          size: pool.respond_to?(:size) ? pool.size : nil,
          stats: stats
        }
      rescue
        nil
      end
    end

    def gather_cache_stats
      return nil unless defined?(::Rails)

      begin
        cache = ::Rails.cache
        return nil unless cache
        stats = if cache.respond_to?(:stats)
                  cache.stats
                elsif cache.respond_to?(:info)
                  cache.info
                else
                  {}
                end
        { backend: cache.class.name, stats: stats }
      rescue
        nil
      end
    end

    def gather_error_count
      # ErrorTracking inspector stores error counts if available
      if defined?(@error_log) && @error_log.is_a?(Array)
        @error_log.size
      else
        0
      end
    end

    def compute_snapshot_diff(a, b, prefix)
      changes = []

      if a.is_a?(Hash) && b.is_a?(Hash)
        all_keys = (a.keys | b.keys)
        all_keys.each do |key|
          va = a[key]
          vb = b[key]
          path = prefix.empty? ? key.to_s : "#{prefix}.#{key}"

          if va.is_a?(Hash) && vb.is_a?(Hash)
            changes.concat(compute_snapshot_diff(va, vb, path))
          elsif va != vb
            changes << {
              metric: path,
              before: va,
              after: vb,
              delta: (va.is_a?(Numeric) && vb.is_a?(Numeric)) ? (vb - va) : nil
            }
          end
        end
      elsif a != b
        changes << {
          metric: prefix,
          before: a,
          after: b,
          delta: (a.is_a?(Numeric) && b.is_a?(Numeric)) ? (b - a) : nil
        }
      end

      changes
    end
  end
end
