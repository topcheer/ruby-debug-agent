require 'timeout'

module DebugAgent
  # CPU profiler inspector. Uses stackprof if available, otherwise falls back
  # to a sampling profiler that periodically captures caller stacks.
  @cpu_profile_data = nil
  @cpu_profile_running = false
  @cpu_profile_lock = Mutex.new

  class << self
    attr_reader :cpu_profile_data, :cpu_profile_running
  end

  register_tool('start_cpu_profile',
                'Start CPU profiling for a given duration. Uses stackprof if available, ' \
                'otherwise falls back to a sampling profiler. Auto-stops after duration.',
                duration_seconds: { type: 'integer', description: 'Profile duration in seconds', required: false }) do |duration_seconds: 10|
    duration = duration_seconds.to_i
    duration = 10 if duration <= 0

    @cpu_profile_lock.synchronize do
      next { error: 'CPU profile already running' } if @cpu_profile_running
      @cpu_profile_running = true
      @cpu_profile_data = nil
    end

    if defined?(::StackProf)
      # StackProf path: block-based profiling
      StackProf.run(mode: :cpu, interval: 1000) do
        sleep(duration)
      end
      @cpu_profile_lock.synchronize { @cpu_profile_running = false }
      raw = StackProf.results
      @cpu_profile_data = parse_stackprof(raw) if raw
      {
        status: 'completed',
        backend: 'stackprof',
        duration_seconds: duration,
        samples: raw ? raw[:samples] : 0
      }
    else
      # Fallback: sampling profiler using caller stacks
      samples = Hash.new(0)
      total_samples = 0
      sample_lock = Mutex.new
      end_time = Time.now + duration

      sampler = Thread.new do
        while Time.now < end_time && @cpu_profile_running
          stack = caller(2)&.join("\n")
          sample_lock.synchronize do
            samples[stack] += 1
            total_samples += 1
          end if stack
          sleep(0.001)
        end
      end

      sampler.join
      @cpu_profile_lock.synchronize { @cpu_profile_running = false }
      @cpu_profile_data = parse_call_samples(samples, total_samples)
      {
        status: 'completed',
        backend: 'sampling',
        duration_seconds: duration,
        total_samples: total_samples,
        unique_stacks: samples.size
      }
    end
  rescue => e
    @cpu_profile_running = false
    { error: e.message }
  end

  register_tool('stop_cpu_profile',
                'Stop CPU profiling and return top 20 methods by self time. ' \
                'Each entry includes method name, file, line, self_ms, total_ms, calls.') do
    next { error: 'No profile data available. Run start_cpu_profile first.' } unless @cpu_profile_data

    @cpu_profile_running = false
    top = (@cpu_profile_data[:functions] || []).first(20)

    {
      status: 'stopped',
      backend: @cpu_profile_data[:backend],
      total_samples: @cpu_profile_data[:total_samples],
      top_functions: top
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_top_functions',
                'Return top methods from last CPU profile. Sort by self_time, total_time, or calls.',
                limit: { type: 'integer', description: 'Number of functions to return (default 20)', required: false },
                sort_by: { type: 'string', description: 'Sort key: self_time, total_time, or calls (default self_time)', required: false }) do |limit: 20, sort_by: 'self_time'|
    next { error: 'No profile data available. Run start_cpu_profile first.' } unless @cpu_profile_data

    funcs = (@cpu_profile_data[:functions] || []).dup
    sort_key = %w[self_time total_time calls].include?(sort_by.to_s) ? sort_by.to_sym : :self_time
    funcs.sort_by! { |f| -f[sort_key].to_f }
    top = funcs.first(limit.to_i > 0 ? limit.to_i : 20)

    {
      sort_by: sort_key,
      total_functions: @cpu_profile_data[:functions]&.size || 0,
      top_functions: top
    }
  rescue => e
    { error: e.message }
  end

  # --- Helpers ---

  class << self
    private

    def parse_stackprof(raw)
      return nil unless raw && raw[:frames]

      funcs = raw[:frames].map do |_frame_key, frame|
        {
          method: frame[:name] || 'unknown',
          file: frame[:file],
          line: frame[:line],
          self_ms: ((frame[:samples].to_f / raw[:samples].to_f) * (raw[:gc_profile_time] || raw[:walltime] || 0) * 1000).round(2),
          total_ms: ((frame[:total_samples].to_f / raw[:samples].to_f) * (raw[:gc_profile_time] || raw[:walltime] || 0) * 1000).round(2),
          calls: frame[:samples].to_i
        }
      end.sort_by { |f| -f[:self_ms] }

      {
        backend: 'stackprof',
        total_samples: raw[:samples],
        functions: funcs
      }
    end

    def parse_call_samples(samples, total_samples)
      method_stats = Hash.new { |h, k| h[k] = { self_time: 0, total_time: 0, calls: 0 } }

      samples.each do |stack_str, count|
        lines = stack_str.split("\n")
        next if lines.empty?

        # First line of caller(2) is the most recently called method
        top_line = lines.first
        parsed = parse_backtrace_line(top_line)

        key = "#{parsed[:file]}:#{parsed[:method]}"
        method_stats[key][:self_time] += count
        method_stats[key][:total_time] += count
        method_stats[key][:calls] += 1

        # All lines contribute to total_time of their respective methods
        lines.each do |line|
          p = parse_backtrace_line(line)
          k = "#{p[:file]}:#{p[:method]}"
          method_stats[k][:total_time] += count
          method_stats[k][:calls] += count unless k == key
        end
      end

      funcs = method_stats.map do |_k, s|
        parsed = parse_backtrace_line(samples.keys.find { |stk| stk.include?(_k) || true }&.split("\n")&.first || '')
        {
          method: _k.split(':').last,
          file: _k.split(':')[0...-1].join(':'),
          line: parsed[:line],
          self_ms: (s[:self_time].to_f / total_samples.to_f * 10000).round(2),
          total_ms: (s[:total_time].to_f / total_samples.to_f * 10000).round(2),
          calls: s[:calls]
        }
      end.sort_by { |f| -f[:self_ms] }

      {
        backend: 'sampling',
        total_samples: total_samples,
        functions: funcs
      }
    end

    def parse_backtrace_line(line)
      # Format: "/path/to/file.rb:42:in `method_name'"
      if line =~ /^(.+):(\d+):in `(.+)'$/
        { file: $1, line: $2.to_i, method: $3 }
      else
        { file: 'unknown', line: 0, method: 'unknown' }
      end
    end
  end
end
