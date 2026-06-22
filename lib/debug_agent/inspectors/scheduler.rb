module DebugAgent
  # Registry of scheduled jobs (Sidekiq::Cron, rufus-scheduler, whenever, or
  # custom Thread-based timers). Applications register jobs so the inspector
  # can list them and report execution history.
  #
  #   DebugAgent.register_scheduled_job(:cleanup, 'every 30s', last_run: Time.now)
  @scheduled_jobs = {}
  @job_history = {}
  @scheduler_lock = Mutex.new

  class << self
    attr_reader :scheduled_jobs, :job_history

    def register_scheduled_job(name, schedule, **opts)
      @scheduled_jobs[name.to_s] = {
        schedule: schedule,
        name: name.to_s,
        class: opts[:class] || name.to_s,
        queue: opts[:queue],
        enabled: opts.key?(:enabled) ? opts[:enabled] : true,
        last_run: opts[:last_run],
        next_run: opts[:next_run],
        registered_at: Time.now
      }
    end

    # Record a job execution for history tracking.
    def record_job_execution(name, duration_ms, success: true, error: nil)
      @scheduler_lock.synchronize do
        history = (@job_history[name.to_s] ||= [])
        history << {
          timestamp: Time.now.iso8601,
          duration_ms: duration_ms.round(2),
          success: success,
          error: error
        }
        history.shift if history.size > 100

        # Update last_run on the job itself
        if @scheduled_jobs[name.to_s]
          @scheduled_jobs[name.to_s][:last_run] = Time.now
        end
      end
    end
  end

  register_tool('get_scheduled_jobs',
                'List scheduled jobs from Sidekiq::Cron, rufus-scheduler, whenever, ' \
                'or custom Thread-based timers. Shows schedule, last run, and status') do
    jobs = []

    # Registered jobs (Thread-based, custom, etc.)
    scheduled_jobs.each do |name, job|
      jobs << {
        name: name,
        schedule: job[:schedule],
        class: job[:class],
        queue: job[:queue],
        enabled: job[:enabled],
        source: job[:source] || 'registered',
        last_run: job[:last_run],
        next_run: job[:next_run]
      }
    end

    # Sidekiq::Cron jobs
    if defined?(::Sidekiq::Cron::Job)
      begin
        ::Sidekiq::Cron::Job.all.each do |cron_job|
          jobs << {
            name: cron_job.name,
            schedule: cron_job.cron,
            class: cron_job.klass,
            queue: cron_job.queue_name,
            enabled: cron_job.status == 'enabled',
            source: 'sidekiq-cron',
            last_run: cron_job.last_enqueue_time
          }
        end
      rescue => e
        jobs << { source: 'sidekiq-cron', error: e.message }
      end
    end

    # rufus-scheduler
    if defined?(::Rufus::Scheduler)
      begin
        ObjectSpace.each_object(::Rufus::Scheduler) do |scheduler|
          scheduler.jobs.each do |job|
            jobs << {
              name: job.respond_to?(:tags) ? job.tags.first : nil,
              schedule: job.respond_to?(:original) ? job.original : job.class.name,
              class: job.class.name,
              enabled: !job.respond_to?(:paused?) || !job.paused?,
              source: 'rufus-scheduler',
              last_run: job.respond_to?(:last_time) ? job.last_time : nil,
              next_run: job.respond_to?(:next_time) ? job.next_time : nil
            }
          end
        end
      rescue => e
        jobs << { source: 'rufus-scheduler', error: e.message }
      end
    end

    if jobs.empty?
      next {
        message: 'No scheduled jobs registered. Call DebugAgent.register_scheduled_job(:name, schedule). ' \
                 'Also auto-detects Sidekiq::Cron and rufus-scheduler if loaded.',
        total: 0
      }
    end

    { total: jobs.size, jobs: jobs }
  rescue => e
    { error: e.message }
  end

  register_tool('get_job_history',
                'Get recent execution history for scheduled jobs: run times, duration, success/failure',
                job_name: { type: 'string', description: 'Job name to filter history (optional, returns all if omitted)', required: false }) do |job_name: nil|
    if job_history.empty?
      next { message: 'No job execution history recorded. Jobs must call DebugAgent.record_job_execution to track history.', total: 0 }
    end

    if job_name
      key = job_name.to_s
      history = job_history[key] || []
      next {
        job: key,
        total: history.size,
        history: history.reverse.first(50)
      }
    end

    all = job_history.map do |name, entries|
      successful = entries.count { |e| e[:success] }
      failed = entries.count { |e| !e[:success] }
      durations = entries.map { |e| e[:duration_ms] }
      {
        job: name,
        total_runs: entries.size,
        successful: successful,
        failed: failed,
        avg_duration_ms: durations.empty? ? 0 : (durations.sum / durations.size.to_f).round(2),
        last_run: entries.last&.dig(:timestamp)
      }
    end

    { total_jobs: all.size, total_runs: job_history.values.map(&:size).sum, jobs: all }
  rescue => e
    { error: e.message }
  end
end
