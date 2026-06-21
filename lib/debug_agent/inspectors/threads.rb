module DebugAgent
  register_tool('get_thread_list',
                'List all threads with status and backtrace summary') do
    threads = Thread.list
    {
      total_threads: threads.size,
      threads: threads.map do |t|
        backtrace = begin
          t.backtrace || []
        rescue => e
          ["<unable to get backtrace: #{e.message}>"]
        end

        {
          object_id: t.object_id,
          to_s: t.to_s,
          status: t.status.nil? ? 'terminated' : t.status.to_s,
          alive: t.alive?,
          priority: t.priority,
          name: (t.name if t.respond_to?(:name)),
          backtrace_summary: backtrace.first(5),
          backtrace_length: backtrace.size
        }
      end
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_thread_count',
                'Get current thread count') do
    threads = Thread.list
    alive = threads.count(&:alive?)
    sleeping = threads.count { |t| t.status == 'sleep' }
    runnable = threads.count { |t| t.status == 'run' }

    {
      total: threads.size,
      alive: alive,
      sleeping: sleeping,
      runnable: runnable,
      main_thread: Thread.main.object_id
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_main_thread_info',
                'Get main thread info: priority, status, name') do
    main = Thread.main
    backtrace = main.backtrace || []

    {
      object_id: main.object_id,
      status: main.status.to_s,
      alive: main.alive?,
      priority: main.priority,
      name: main.respond_to?(:name) ? main.name : nil,
      backtrace_length: backtrace.size,
      backtrace_top: backtrace.first(10),
      thread_group: main.group.to_s,
      ruby_thread_id: (main.respond_to?(:native_thread_id) ? main.native_thread_id : nil)
    }
  rescue => e
    { error: e.message }
  end
end
