require 'objspace'

module DebugAgent
  register_tool('get_gc_stats',
                'Get detailed GC statistics: count, heap pages, slots, total allocated objects') do
    stats = GC.stat
    {
      count: stats[:count],
      major_gc_count: stats[:major_gc_count],
      minor_gc_count: stats[:minor_gc_count],
      total_allocated_objects: stats[:total_allocated_objects],
      total_freed_objects: stats[:total_freed_objects],
      heap_allocation_pages: stats[:heap_length],
      heap_eden_pages: stats[:heap_eden_pages],
      heap_tomb_pages: stats[:heap_tomb_pages],
      total_slots: stats[:heap_length] * 512,
      live_slots: stats[:heap_live_slots],
      free_slots: stats[:heap_free_slots],
      old_objects: stats[:old_objects],
      old_objects_limit: stats[:old_objects_limit],
      malloc_increase_bytes: stats[:malloc_increase_bytes],
      malloc_increase_bytes_limit: stats[:malloc_increase_bytes_limit]
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_gc_profiler',
                'Get GC::Profiler data if profiling is enabled (GC timing details)') do
    if defined?(GC::Profiler)
      raw_data = GC::Profiler.raw_data
      total_time = GC::Profiler.total_time
      if raw_data && !raw_data.empty?
        {
          enabled: true,
          total_gc_time_seconds: total_time.round(6),
          gc_count: raw_data.size,
          entries: raw_data.map do |entry|
            {
              gc_time: entry[:GC_TIME]&.round(6),
              gc_invoke_time: entry[:GC_INVOKE_TIME]&.round(6),
              heap_use_pages: entry[:HEAP_USE_PAGES],
              heap_live_objects: entry[:HEAP_LIVE_OBJECTS],
              heap_free_objects: entry[:HEAP_FREE_OBJECTS],
              heap_total_objects: entry[:HEAP_TOTAL_OBJECTS],
              gc_mark_time: entry[:GC_MARK_TIME]&.round(6),
              gc_sweep_time: entry[:GC_SWEEP_TIME]&.round(6)
            }
          end
        }
      else
        {
          enabled: true,
          message: 'GC::Profiler is available but has no data. Call GC::Profiler.enable to start collecting.',
          total_gc_time_seconds: 0
        }
      end
    else
      { enabled: false, message: 'GC::Profiler is not available on this Ruby implementation' }
    end
  rescue => e
    { error: e.message }
  end

  register_tool('force_gc',
                'Trigger a full garbage collection (GC.start with full_mark) and show before/after comparison') do
    before_stats = GC.stat
    before_objects = ObjectSpace.count_objects.values.sum

    GC.start(full_mark: true)
    GC.start(full_mark: true)  # Second call to compact and finalize

    after_stats = GC.stat
    after_objects = ObjectSpace.count_objects.values.sum

    {
      triggered: true,
      objects_before: before_objects,
      objects_after: after_objects,
      freed_objects: before_objects - after_objects,
      gc_count_before: before_stats[:count],
      gc_count_after: after_stats[:count],
      live_slots_before: before_stats[:heap_live_slots],
      live_slots_after: after_stats[:heap_live_slots],
      freed_slots: before_stats[:heap_live_slots] - after_stats[:heap_live_slots]
    }
  rescue => e
    { error: e.message }
  end
end
