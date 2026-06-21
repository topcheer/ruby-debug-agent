require 'gc'
require 'objspace'
require 'thread'

module DebugAgent
  register_tool('get_gc_stats', 'Get GC statistics: count, time, live objects') do
    stats = GC.stat
    {
      count: stats[:count],
      major_gc_count: stats[:major_gc_count],
      minor_gc_count: stats[:minor_gc_count],
      total_allocated_objects: stats[:total_allocated_objects],
      live_objects: ObjectSpace.count_objects[:T_OBJECT] || 0,
      heap_pages: stats[:heap_length],
      total_freed_objects: stats[:total_freed_objects]
    }
  end

  register_tool('get_memory_summary', 'Get process memory usage: RSS, object counts') do
    rss = `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
    counts = ObjectSpace.count_objects
    top_types = counts.sort_by { |_, v| -v }.first(15).to_h
    {
      rss_mb: rss.round(2),
      total_objects: counts.values.sum,
      top_object_types: top_types,
      live_strings: counts[:T_STRING] || 0,
      live_arrays: counts[:T_ARRAY] || 0,
      live_hashes: counts[:T_HASH] || 0
    }
  end

  register_tool('trigger_gc', 'Trigger GC and show before/after comparison') do
    before = ObjectSpace.count_objects.values.sum
    GC.start
    after = ObjectSpace.count_objects.values.sum
    {
      objects_before: before,
      objects_after: after,
      freed: before - after,
      gc_count: GC.stat[:count]
    }
  end

  register_tool('get_thread_summary', 'Get thread count and list') do
    threads = Thread.list
    {
      total_threads: threads.size,
      threads: threads.map do |t|
        { name: t.to_s, alive: t.alive?, status: t.status }
      end
    }
  end

  register_tool('get_runtime_info', 'Get Ruby runtime info: version, platform, PID') do
    {
      ruby_version: RUBY_VERSION,
      ruby_engine: RUBY_ENGINE,
      platform: RUBY_PLATFORM,
      pid: Process.pid,
      process_name: $0,
      load_path_count: $LOAD_PATH.size
    }
  rescue
    {
      ruby_version: RUBY_VERSION,
      ruby_engine: RUBY_ENGINE,
      platform: RUBY_PLATFORM,
      pid: Process.pid
    }
  end

  register_tool('get_object_allocations',
                'Get top memory allocation sites using ObjectSpace tracing') do
    # Snapshot current allocation statistics
    stats = ObjectSpace.count_objects
    {
      total_objects: stats.values.sum,
      by_type: stats.sort_by { |_, v| -v }.first(20).map { |k, v| { type: k, count: v } }
    }
  end
end
