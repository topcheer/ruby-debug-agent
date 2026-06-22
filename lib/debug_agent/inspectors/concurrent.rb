module DebugAgent
  # Inspector for the concurrent-ruby gem: global executor pools and any
  # registered promises/futures.
  #
  #   DebugAgent.register_concurrent(:my_task, Concurrent::Promises.future { ... })
  @concurrent_promises = {}

  class << self
    attr_reader :concurrent_promises

    def register_concurrent(name, promise)
      @concurrent_promises[name.to_s] = promise
    end

    def executor_info(executor)
      return nil unless executor
      info = { class: executor.class.name }
      %i[running?].each do |m|
        info[m] = executor.public_send(m) if executor.respond_to?(m)
      end
      %i[length largest_length queue_length scheduled_task_count completed_task_count
         max_threads min_threads idletime max_queue].each do |m|
        info[m] = (executor.public_send(m) rescue nil) if executor.respond_to?(m)
      end
      info
    rescue => e
      { class: executor&.class&.name, error: e.message }
    end

    def promise_info(name, promise)
      info = { name: name, class: promise.class.name }
      info[:state] = promise.state if promise.respond_to?(:state)
      if promise.respond_to?(:fulfilled?)
        info[:fulfilled] = promise.fulfilled?
        info[:rejected] = promise.rejected? if promise.respond_to?(:rejected?)
        info[:pending] = promise.pending? if promise.respond_to?(:pending?)
      end
      if promise.respond_to?(:reason)
        reason = promise.reason
        info[:reason] = reason.is_a?(Exception) ? reason.message : reason.inspect unless reason.nil?
      end
      info
    rescue => e
      { name: name, error: e.message }
    end
  end

  register_tool('get_concurrent_state',
                'If concurrent-ruby is loaded, list global executor pools and registered ' \
                'promises/futures with their state') do
    next { error: 'concurrent-ruby is not loaded (concurrent-ruby gem not installed)' } unless defined?(::Concurrent)

    executors = {}
    if ::Concurrent.respond_to?(:global_io_executor)
      executors[:global_io] = executor_info(::Concurrent.global_io_executor)
    end
    if ::Concurrent.respond_to?(:global_fast_executor)
      executors[:global_fast] = executor_info(::Concurrent.global_fast_executor)
    end
    if ::Concurrent.respond_to?(:global_immediate_executor)
      executors[:global_immediate] = executor_info(::Concurrent.global_immediate_executor)
    end

    promises =
      if concurrent_promises.empty?
        { message: 'No promises/futures registered. Call DebugAgent.register_concurrent(:name, future).' }
      else
        concurrent_promises.map { |n, p| promise_info(n, p) }
      end

    {
      executors: executors,
      registered_promises: promises
    }
  rescue => e
    { error: e.message }
  end
end
