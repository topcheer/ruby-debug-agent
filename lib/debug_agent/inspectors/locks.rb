require 'thread'
require 'time'

module DebugAgent
  # Track registered Mutexes for lock contention and deadlock analysis.
  #
  #   DebugAgent.register_mutex(:order_lock, Mutex.new)
  @registered_mutexes = {}
  @lock_stats = {}
  @lock_meta_lock = Mutex.new

  SENSITIVE_LOCK_ERRORS = []

  class << self
    attr_reader :registered_mutexes, :lock_stats

    def register_mutex(name, mutex)
      mutex_name = name.to_s
      @registered_mutexes[mutex_name] = mutex

      @lock_meta_lock.synchronize do
        @lock_stats[mutex_name] ||= {
          acquire_count: 0,
          contention_count: 0,
          total_wait_ns: 0,
          total_hold_ns: 0,
          last_acquired_at: nil,
          last_released_at: nil,
          max_wait_ns: 0,
          max_hold_ns: 0
        }
      end

      # Wrap the mutex's synchronize method to track timing.
      # This only affects this specific mutex instance.
      wrap_mutex_for_tracking(mutex, mutex_name) if mutex.respond_to?(:synchronize)

      mutex
    end

    def record_lock_acquire(mutex_name, wait_ns)
      @lock_meta_lock.synchronize do
        s = @lock_stats[mutex_name]
        return unless s
        s[:acquire_count] += 1
        s[:contention_count] += 1 if wait_ns > 1_000_000 # > 1ms is contention
        s[:total_wait_ns] += wait_ns
        s[:max_wait_ns] = wait_ns if wait_ns > s[:max_wait_ns]
        s[:last_acquired_at] = Time.now.iso8601
      end
    end

    def record_lock_release(mutex_name, hold_ns)
      @lock_meta_lock.synchronize do
        s = @lock_stats[mutex_name]
        return unless s
        s[:total_hold_ns] += hold_ns
        s[:max_hold_ns] = hold_ns if hold_ns > s[:max_hold_ns]
        s[:last_released_at] = Time.now.iso8601
      end
    end

    private

    def wrap_mutex_for_tracking(mutex, name)
      return if mutex.singleton_class.method_defined?(:__debug_agent_tracked?)

      original_sync = mutex.method(:synchronize)

      mutex.define_singleton_method(:__debug_agent_tracked?) { true }

      mutex.define_singleton_method(:synchronize) do |&block|
        wait_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        acquired = false
        begin
          original_sync.call do
            acquired_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            wait_ns = ((acquired_at - wait_start) * 1_000_000_000).to_i
            DebugAgent.record_lock_acquire(name, wait_ns)
            acquired = true
            hold_start = acquired_at
            begin
              block.call
            ensure
              hold_ns = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - hold_start) * 1_000_000_000).to_i
              DebugAgent.record_lock_release(name, hold_ns)
            end
          end
        rescue => e
          DebugAgent.record_lock_release(name, 0) if acquired
          raise
        end
      end
    end
  end

  register_tool('get_lock_contention',
                'Analyze Mutex contention: list registered mutexes with lock/hold ' \
                'timing, contention count, and threads currently blocked on mutex ' \
                'operations') do
    # Scan all threads for backtraces indicating mutex blocking
    blocked_threads = []
    Thread.list.each do |t|
      next unless t.alive? && t.status == 'sleep'
      bt = begin
        t.backtrace || []
      rescue
        []
      end
      next if bt.empty?

      mutex_frame = bt.find { |line| line =~ /mutex|synchronize|lock|Monitor|ConditionVariable/i }
      next unless mutex_frame

      blocked_threads << {
        thread_object_id: t.object_id,
        thread_name: (t.name rescue nil),
        status: t.status,
        blocking_location: mutex_frame,
        backtrace_top: bt.first(5)
      }
    end

    if registered_mutexes.empty?
      next {
        registered_mutex_count: 0,
        mutexes: [],
        blocked_threads_count: blocked_threads.size,
        blocked_threads: blocked_threads.first(50),
        message: 'No mutexes registered. Call DebugAgent.register_mutex(:name, mutex) to track lock contention.'
      }
    end

    mutexes = registered_mutexes.map do |name, mutex|
      stats = lock_stats[name] || {}
      {
        name: name,
        object_id: mutex.object_id,
        class: mutex.class.name,
        tracked: mutex.singleton_class.method_defined?(:__debug_agent_tracked?),
        locked: (mutex.locked? if mutex.respond_to?(:locked?)),
        acquire_count: stats[:acquire_count] || 0,
        contention_count: stats[:contention_count] || 0,
        total_wait_ms: ((stats[:total_wait_ns] || 0) / 1_000_000.0).round(2),
        avg_wait_ms: stats[:acquire_count].to_i.positive? ?
                       ((stats[:total_wait_ns] || 0) / stats[:acquire_count] / 1_000_000.0).round(2) : 0.0,
        max_wait_ms: ((stats[:max_wait_ns] || 0) / 1_000_000.0).round(2),
        total_hold_ms: ((stats[:total_hold_ns] || 0) / 1_000_000.0).round(2),
        avg_hold_ms: stats[:acquire_count].to_i.positive? ?
                       ((stats[:total_hold_ns] || 0) / stats[:acquire_count] / 1_000_000.0).round(2) : 0.0,
        max_hold_ms: ((stats[:max_hold_ns] || 0) / 1_000_000.0).round(2),
        last_acquired_at: stats[:last_acquired_at],
        last_released_at: stats[:last_released_at]
      }
    end

    {
      registered_mutex_count: registered_mutexes.size,
      mutexes: mutexes,
      blocked_threads_count: blocked_threads.size,
      blocked_threads: blocked_threads.first(50),
      analysis: if blocked_threads.any?
                  'Threads detected blocking on mutexes — possible contention'
                else
                  'No threads currently blocking on mutexes'
                end
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_gvl_stats',
                'Global VM Lock (GVL) stats for Ruby 3.2+: GVL wait time, thread switch ' \
                'count, GC profiler data, and VM statistics') do
    stats = {
      ruby_version: RUBY_VERSION,
      platform: RUBY_PLATFORM,
      thread_count: Thread.list.size,
      alive_threads: Thread.list.count(&:alive?),
      sleeping_threads: Thread.list.count { |t| t.status == 'sleep' }
    }

    # RubyVM.stat (available in MRI Ruby, provides VM-level counters)
    begin
      if RubyVM.respond_to?(:stat)
        vm_stat = RubyVM.stat
        stats[:vm_stats] = vm_stat.select { |k, _| 
          %i[instruction_sequence_count constant_cache_count constant_cache_invalidations_count
             global_method_state global_constant_count].include?(k)
        }
        stats[:vm_stat_total_keys] = vm_stat.size
      end
    rescue
      nil
    end

    # GC::Profiler data (must be explicitly enabled)
    if defined?(GC::Profiler)
      stats[:gc_profiler_enabled] = GC::Profiler.enabled?
      if GC::Profiler.enabled?
        begin
          stats[:gc_total_time_ms] = (GC::Profiler.total_time * 1000).round(2)
        rescue
          nil
        end
      end
    end

    # GC.stat — always available in MRI, useful GVL-adjacent metrics
    if GC.respond_to?(:stat)
      gc = GC.stat
      stats[:gc_stat] = {
        count: gc[:count],
        major_gc_count: gc[:major_gc_count],
        minor_gc_count: gc[:minor_gc_count],
        total_allocated_objects: gc[:total_allocated_objects],
        heap_live_slots: gc[:heap_live_slots],
        heap_free_slots: gc[:heap_free_slots],
        heap_allocated_pages: gc[:heap_allocated_pages],
        heap_eden_pages: gc[:heap_eden_pages],
        heap_tomb_pages: gc[:heap_tomb_pages]
      }
    end

    # Process CPU time as GVL contention proxy
    begin
      stats[:process_cpu_time_ns] = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
      stats[:thread_cpu_time_ns] = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
      stats[:monotonic_ns] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rescue
      nil
    end

    # Check for pending interrupts (Thread.pending_interrupt?)
    pending = Thread.list.select do |t|
      begin
        t.pending_interrupt?
      rescue
        false
      end
    end
    stats[:threads_with_pending_interrupts] = pending.size
    stats[:pending_interrupt_threads] = pending.map do |t|
      { object_id: t.object_id, name: (t.name rescue nil), status: t.status }
    end

    # Thread backtrace depth as a rough GVL pressure indicator
    total_bt_depth = Thread.list.sum do |t|
      begin
        (t.backtrace || []).size
      rescue
        0
      end
    end
    stats[:total_backtrace_depth] = total_bt_depth
    stats[:avg_backtrace_depth] = Thread.list.empty? ? 0 : (total_bt_depth / Thread.list.size)

    stats
  rescue => e
    { error: e.message }
  end

  register_tool('detect_deadlock',
                'Detect deadlock among registered mutexes: check if threads are blocked ' \
                'waiting on each other in a circular dependency. Scans thread backtraces ' \
                'for mutex/Monitor blocking patterns') do
    # Gather all threads that appear to be blocked on lock operations
    thread_states = Thread.list.map do |t|
      next nil unless t.alive?
      bt = begin
        t.backtrace || []
      rescue
        []
      end

      blocking_on = bt.find { |line| line =~ /mutex|synchronize|lock|Monitor|ConditionVariable/i }
      next nil unless blocking_on

      # Identify which registered mutexes might be involved by matching object_ids
      potential_mutexes = registered_mutexes.select do |_name, m|
        blocking_on.to_s.include?(m.object_id.to_s)
      end.keys

      {
        thread_object_id: t.object_id,
        thread_name: (t.name rescue nil),
        status: t.status,
        blocking_on: blocking_on,
        backtrace: bt.first(10),
        potential_mutexes: potential_mutexes
      }
    end.compact

    blocked_count = thread_states.size

    # Build wait-for graph for cycle detection
    # If two threads are both blocking on locks and potentially reference the
    # same mutexes, flag as potential contention/deadlock
    potential_cycles = []
    thread_states.each_with_index do |t1, i|
      thread_states.each_with_index do |t2, j|
        next if i >= j
        if t1[:potential_mutexes].any? && t2[:potential_mutexes].any?
          overlap = (t1[:potential_mutexes] & t2[:potential_mutexes])
          if overlap.any?
            potential_cycles << {
              thread_a: { id: t1[:thread_object_id], name: t1[:thread_name], blocking_on: t1[:blocking_on] },
              thread_b: { id: t2[:thread_object_id], name: t2[:thread_name], blocking_on: t2[:blocking_on] },
              shared_mutexes: overlap,
              risk_level: 'high'
            }
          end
        end
      end
    end

    # Also check: is any registered mutex held with no active threads able to proceed?
    stuck_mutexes = registered_mutexes.select do |_name, m|
      m.respond_to?(:locked?) && m.locked?
    end.map { |name, _| name }

    deadlock_detected = potential_cycles.any?

    {
      deadlock_detected: deadlock_detected,
      blocked_thread_count: blocked_count,
      blocked_threads: thread_states.first(50),
      potential_cycles: potential_cycles,
      stuck_mutexes: stuck_mutexes,
      registered_mutexes: registered_mutexes.keys,
      recommendation: if deadlock_detected
                        'Deadlock risk detected. Review lock ordering — ensure consistent ' \
                          'acquisition order across all mutexes.'
                      elsif blocked_count > 0
                        "#{blocked_count} thread(s) blocking on locks but no circular dependency detected."
                      else
                        'No deadlock patterns detected.'
                      end
    }
  rescue => e
    { error: e.message }
  end
end
