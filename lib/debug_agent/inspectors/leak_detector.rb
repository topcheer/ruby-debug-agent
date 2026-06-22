require 'objspace'

module DebugAgent
  # Memory leak detector inspector. Records heap snapshots and compares them
  # to identify object types with consistent growth.
  @heap_snapshots = {}
  @heap_snapshot_counter = 0

  class << self
    attr_reader :heap_snapshots
  end

  register_tool('take_heap_snapshot',
                'Take a heap snapshot recording object counts by type, heap slots, ' \
                'and GC counts. Returns a snapshot ID for later comparison.') do
    counts = Hash.new(0)
    ObjectSpace.each_object do |obj|
      begin
        name = obj.class.name || obj.class.to_s
        counts[name] += 1
      rescue
        counts['<unknown>'] += 1
      end
    end

    gc_stats = GC.stat
    total_objects = counts.values.sum

    @heap_snapshot_counter += 1
    snapshot_id = "heap-#{@heap_snapshot_counter}"

    snapshot = {
      id: snapshot_id,
      taken_at: Time.now,
      object_counts: counts,
      total_objects: total_objects,
      live_slots: gc_stats[:heap_live_slots],
      free_slots: gc_stats[:heap_free_slots],
      total_slots: gc_stats[:heap_live_slots].to_i + gc_stats[:heap_free_slots].to_i,
      gc_count: gc_stats[:count],
      major_gc_count: gc_stats[:major_gc_count],
      minor_gc_count: gc_stats[:minor_gc_count],
      total_allocated_objects: gc_stats[:total_allocated_objects],
      total_freed_objects: gc_stats[:total_freed_objects],
      heap_pages: gc_stats[:heap_length]
    }

    @heap_snapshots[snapshot_id] = snapshot

    {
      snapshot_id: snapshot_id,
      taken_at: snapshot[:taken_at].iso8601,
      summary: {
        total_objects: total_objects,
        total_classes: counts.size,
        live_slots: snapshot[:live_slots],
        free_slots: snapshot[:free_slots],
        gc_count: snapshot[:gc_count],
        top_types: counts.sort_by { |_, v| -v }.first(10).to_h
      }
    }
  rescue => e
    { error: e.message }
  end

  register_tool('compare_heap_snapshots',
                'Compare two heap snapshots. Returns per-type count delta and growth ' \
                'percentage, sorted by absolute growth.',
                snapshot_a: { type: 'string', description: 'First snapshot ID', required: true },
                snapshot_b: { type: 'string', description: 'Second snapshot ID', required: true }) do |snapshot_a:, snapshot_b:|
    snap_a = @heap_snapshots[snapshot_a.to_s]
    snap_b = @heap_snapshots[snapshot_b.to_s]

    next { error: "Snapshot '#{snapshot_a}' not found. Available: #{@heap_snapshots.keys.join(', ')}" } unless snap_a
    next { error: "Snapshot '#{snapshot_b}' not found. Available: #{@heap_snapshots.keys.join(', ')}" } unless snap_b

    counts_a = snap_a[:object_counts]
    counts_b = snap_b[:object_counts]

    all_types = (counts_a.keys | counts_b.keys).uniq
    deltas = all_types.map do |type|
      ca = counts_a[type] || 0
      cb = counts_b[type] || 0
      delta = cb - ca
      growth_pct = ca > 0 ? (delta.to_f / ca * 100).round(2) : (delta > 0 ? Float::INFINITY : 0.0)

      {
        type: type,
        count_before: ca,
        count_after: cb,
        count_delta: delta,
        growth_percentage: growth_pct
      }
    end

    # Sort by absolute growth descending
    deltas.sort_by! { |d| -d[:count_delta].abs }

    {
      snapshot_a: snapshot_a,
      snapshot_b: snapshot_b,
      time_between: (snap_b[:taken_at] - snap_a[:taken_at]).round(2),
      summary: {
        total_objects_before: snap_a[:total_objects],
        total_objects_after: snap_b[:total_objects],
        net_delta: snap_b[:total_objects] - snap_a[:total_objects],
        gc_runs_between: snap_b[:gc_count] - snap_a[:gc_count],
        live_slots_delta: snap_b[:live_slots] - snap_a[:live_slots]
      },
      type_changes: deltas.first(50)
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_leak_candidates',
                'Identify object types with consistent growth across stored snapshots. ' \
                'Shows top growing object types.') do |snapshot_limit: 10|
    next { error: 'Need at least 2 snapshots to detect trends' } if @heap_snapshots.size < 2

    snapshots = @heap_snapshots.values.sort_by { |s| s[:taken_at] }
    snapshots = snapshots.last([snapshot_limit.to_i, 2].max)

    # For each type, compute growth across consecutive snapshot pairs
    type_growth = Hash.new { |h, k| h[k] = { deltas: [], total_growth: 0 } }

    snapshots.each_cons(2) do |s1, s2|
      all_types = (s1[:object_counts].keys | s2[:object_counts].keys)
      all_types.each do |type|
        c1 = s1[:object_counts][type] || 0
        c2 = s2[:object_counts][type] || 0
        delta = c2 - c1
        type_growth[type][:deltas] << delta
        type_growth[type][:total_growth] += delta
      end
    end

    candidates = type_growth
                 .select { |_, g| g[:total_growth] > 0 && g[:deltas].all? { |d| d >= 0 } }
                 .map do |type, g|
                   {
                     type: type,
                     total_growth: g[:total_growth],
                     snapshots_growing: g[:deltas].count(&:positive?),
                     total_snapshots_compared: g[:deltas].size,
                     consistency: g[:deltas].all?(&:positive?) ? 'consistent' : 'partial',
                     per_period_deltas: g[:deltas]
                   }
                 end
                 .sort_by { |c| -c[:total_growth] }

    {
      snapshots_analyzed: snapshots.size,
      first_snapshot: snapshots.first[:id],
      last_snapshot: snapshots.last[:id],
      leak_candidates: candidates.first(20)
    }
  rescue => e
    { error: e.message }
  end
end
