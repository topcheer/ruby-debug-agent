require 'time'
require 'thread'

module DebugAgent
  MAX_REQUESTS = 500
  @request_buffer = []
  @buffer_lock = Mutex.new

  module HttpRequestTracker
    def self.record(method, path, status, duration_ms, client = '')
      DebugAgent.instance_variable_get(:@buffer_lock).synchronize do
        buffer = DebugAgent.instance_variable_get(:@request_buffer)
        buffer << {
          timestamp: Time.now.iso8601,
          method: method,
          path: path,
          status: status,
          duration_ms: duration_ms.round(2),
          client: client
        }
        buffer.shift if buffer.size > MAX_REQUESTS
      end
    end

    def self.all
      DebugAgent.instance_variable_get(:@buffer_lock).synchronize do
        DebugAgent.instance_variable_get(:@request_buffer).dup
      end
    end
  end

  register_tool('get_recent_requests', 'Get recent HTTP requests from ring buffer') do |limit: 50|
    reqs = HttpRequestTracker.all
    reqs = reqs.last(limit) if limit
    {
      total: HttpRequestTracker.all.size,
      requests: reqs.reverse
    }
  end

  register_tool('get_error_requests', 'Get error requests (4xx/5xx)') do
    reqs = HttpRequestTracker.all.select { |r| r[:status] >= 400 }
    {
      count: reqs.size,
      requests: reqs.sort_by { |r| -r[:duration_ms] }
    }
  end

  register_tool('get_request_stats', 'Get HTTP request stats: P50/P95/P99 latency, error rate') do
    reqs = HttpRequestTracker.all
    next({ message: 'No requests recorded yet' }) if reqs.empty?

    durations = reqs.map { |r| r[:duration_ms] }.sort
    n = durations.size
    errors = reqs.count { |r| r[:status] >= 400 }

    {
      total_requests: n,
      error_count: errors,
      error_rate: format('%.1f%%', errors.to_f / n * 100),
      latency_ms: {
        min: durations[0].round(2),
        p50: durations[(n * 0.5).to_i].round(2),
        p95: durations[(n * 0.95).to_i].round(2),
        p99: durations[(n * 0.99).to_i].round(2),
        max: durations[-1].round(2)
      }
    }
  end
end
