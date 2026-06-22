module DebugAgent
  # Registry of health check blocks. Each block returns a hash with at least
  # a :status key ('UP', 'DOWN', or 'DEGRADED').
  #
  #   DebugAgent.register_health_check(:database) { { status: 'UP' } }
  @health_checks = {}

  class << self
    attr_reader :health_checks

    def register_health_check(name, &block)
      @health_checks[name.to_s] = block
    end
  end

  register_tool('get_health_status',
                'Run all registered health checks and report status per component: UP, DOWN, or DEGRADED') do
    if health_checks.empty?
      next {
        message: 'No health checks registered. Call DebugAgent.register_health_check(:name) { ... }.',
        overall_status: 'UNKNOWN'
      }
    end

    results = {}
    up = 0
    down = 0
    degraded = 0

    health_checks.each do |check_name, block|
      begin
        result = block.call
        status = result.is_a?(Hash) ? (result[:status] || result['status'] || 'UP').to_s.upcase : 'UP'
        results[check_name] = result.merge(status: status, latency_ms: nil)

        case status
        when 'UP' then up += 1
        when 'DOWN' then down += 1
        when 'DEGRADED' then degraded += 1
        end
      rescue => e
        results[check_name] = { status: 'DOWN', error: e.message }
        down += 1
      end
    end

    overall = if down > 0
      'DOWN'
    elsif degraded > 0
      'DEGRADED'
    else
      'UP'
    end

    {
      overall_status: overall,
      up: up,
      down: down,
      degraded: degraded,
      total: health_checks.size,
      components: results
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_health_detail',
                'Deep dive into a specific health check component for detailed diagnostics',
                component_name: { type: 'string', description: 'Name of the health check component to inspect', required: true }) do |component_name:|
    if health_checks.empty?
      next { error: 'No health checks registered.' }
    end

    key = component_name.to_s
    block = health_checks[key]
    next { error: "No health check registered for '#{component_name}'. Available: #{health_checks.keys.join(', ')}" } unless block

    # Run the check multiple times to measure latency
    samples = []
    3.times do
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        result = block.call
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0).round(2)
        status = result.is_a?(Hash) ? (result[:status] || result['status'] || 'UP').to_s.upcase : 'UP'
        samples << { status: status, latency_ms: elapsed, detail: result }
      rescue => e
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0).round(2)
        samples << { status: 'DOWN', latency_ms: elapsed, error: e.message }
        break
      end
    end

    latencies = samples.map { |s| s[:latency_ms] }

    {
      component: key,
      registered_checks: health_checks.keys,
      latest: samples.last,
      samples: samples.size,
      latency_ms: {
        min: latencies.min,
        avg: (latencies.sum / latencies.size.to_f).round(2),
        max: latencies.max
      }
    }
  rescue => e
    { error: e.message }
  end
end
