module DebugAgent
  # Registry for Sidekiq queue objects (Sidekiq::Queue instances). Applications
  # register named queues so the inspector can read live stats.
  #
  #   DebugAgent.register_sidekiq_queue(:default, Sidekiq::Queue.new('default'))
  @sidekiq_queues = {}

  class << self
    attr_reader :sidekiq_queues

    def register_sidekiq_queue(name, queue)
      @sidekiq_queues[name.to_s] = queue
    end
  end

  register_tool('get_sidekiq_queues',
                'Get Sidekiq queue stats: processed, failed, enqueued totals and ' \
                'per-queue sizes (requires sidekiq)') do
    unless defined?(::Sidekiq)
      return { error: 'Sidekiq is not loaded (sidekiq gem not installed)' }
    end

    stats = ::Sidekiq::Stats.new

    queues =
      if sidekiq_queues.any?
        sidekiq_queues.map do |name, queue|
          {
            name: name,
            size: queue.size,
            latency_seconds: queue.latency.to_f.round(3)
          }
        end
      else
        ::Sidekiq::Queue.all.map do |queue|
          {
            name: queue.name,
            size: queue.size,
            latency_seconds: queue.latency.to_f.round(3)
          }
        end
      end

    {
      processed: stats.processed,
      failed: stats.failed,
      enqueued: stats.enqueued,
      queues: queues
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_sidekiq_workers',
                'Get Sidekiq worker stats: busy workers, processes, total concurrency ' \
                '(requires sidekiq)') do
    unless defined?(::Sidekiq)
      return { error: 'Sidekiq is not loaded (sidekiq gem not installed)' }
    end

    processes = ::Sidekiq::ProcessSet.new.to_a

    total_busy = processes.sum(&:busy)
    total_concurrency = processes.sum(&:concurrency)

    process_list = processes.map do |p|
      {
        identity: p.identity,
        hostname: p['hostname'],
        pid: p['pid'],
        started_at: p['started_at'],
        concurrency: p.concurrency,
        busy: p.busy,
        queues: p['queues'] || []
      }
    end

    {
      busy: total_busy,
      processes: process_list.size,
      total_concurrency: total_concurrency,
      process_list: process_list
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_sidekiq_retries',
                'Get Sidekiq retry set: count and sample jobs (requires sidekiq)') do |sample_size: 10|
    unless defined?(::Sidekiq)
      return { error: 'Sidekiq is not loaded (sidekiq gem not installed)' }
    end

    retry_set = ::Sidekiq::RetrySet.new
    sample_size = sample_size.to_i
    sample_size = 10 if sample_size <= 0

    samples = []
    retry_set.first(sample_size).each do |job|
      samples << {
        class: job.klass,
        queue: job.queue,
        args: job.args,
        retry_count: job['retry_count'],
        failed_at: job['failed_at'],
        next_retry: job['next_at'] || job.at,
        jid: job.jid,
        error_message: job['error_message'],
        error_class: job['error_class']
      }
    end

    {
      retry_count: retry_set.size,
      sample_size: samples.size,
      sample_jobs: samples
    }
  rescue => e
    { error: e.message }
  end
end
