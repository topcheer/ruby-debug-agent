require 'time'
require 'thread'

module DebugAgent
  # Track outbound Net::HTTP calls (latency, errors, hosts) and live
  # connections by wrapping Net::HTTP#request, #start and #finish.
  @outbound_stats = { total: 0, latencies: [], errors: 0, hosts: {} }
  @outbound_lock = Mutex.new
  @http_connections = {}

  class << self
    attr_reader :outbound_stats

    def record_outbound(http, req, latency_ms, error)
      @outbound_lock.synchronize do
        s = @outbound_stats
        s[:total] += 1
        s[:latencies] << latency_ms
        s[:latencies].shift if s[:latencies].size > 1000

        host_key = "#{http.address}:#{http.port}"
        h = (s[:hosts][host_key] ||= { count: 0, latencies: [], errors: 0 })
        h[:count] += 1
        h[:latencies] << latency_ms
        h[:latencies].shift if h[:latencies].size > 200
        if error
          s[:errors] += 1
          h[:errors] += 1
        end
      end
    end

    def track_http_connect(http)
      @outbound_lock.synchronize do
        @http_connections[http.object_id] = {
          host: http.address,
          port: http.port,
          use_ssl: http.use_ssl?,
          started_at: Time.now.iso8601,
          active: true
        }
      end
    end

    def track_http_disconnect(http)
      @outbound_lock.synchronize do
        conn = @http_connections[http.object_id]
        conn[:active] = false if conn
      end
    end

    # Wrap Net::HTTP once to capture outbound request metrics.
    def install_outbound_tracker
      return false unless defined?(::Net::HTTP)
      return true if ::Net::HTTP.include?(OutboundHttpTracker)

      ::Net::HTTP.prepend(OutboundHttpTracker)
      true
    end
  end

  # Prepended module that instruments Net::HTTP request lifecycle.
  module OutboundHttpTracker
    def start
      DebugAgent.track_http_connect(self) rescue nil
      super
    end

    def finish
      DebugAgent.track_http_disconnect(self) rescue nil
      super
    end

    def request(req, *args, &block)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        result = super
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0)
        DebugAgent.record_outbound(self, req, elapsed, nil) rescue nil
        result
      rescue => e
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0)
        DebugAgent.record_outbound(self, req, elapsed, e) rescue nil
        raise
      end
    end
  end

  # Auto-install the tracker at load time when Net::HTTP is available.
  install_outbound_tracker

  register_tool('get_http_connections',
                'List Net::HTTP connections and their state: host, port, use_ssl, ' \
                'start_time, active connections') do
    conns = @outbound_lock.synchronize { @http_connections.values }
    active = conns.select { |c| c[:active] }
    {
      active_count: active.size,
      total_tracked: conns.size,
      tracker_active: defined?(::Net::HTTP) && ::Net::HTTP.include?(OutboundHttpTracker),
      connections: conns.last(200)
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_outbound_summary',
                'Summary of outbound HTTP calls tracked by the agent: total, avg latency, ' \
                'error rate, top hosts') do
    snapshot = @outbound_lock.synchronize do
      {
        total: @outbound_stats[:total],
        latencies: @outbound_stats[:latencies].dup,
        errors: @outbound_stats[:errors],
        hosts: @outbound_stats[:hosts].transform_values(&:dup)
      }
    end

    lats = snapshot[:latencies]
    avg = lats.empty? ? 0.0 : (lats.sum / lats.size)
    total = snapshot[:total]

    top_hosts = snapshot[:hosts].map do |host, info|
      hl = info[:latencies]
      {
        host: host,
        count: info[:count],
        avg_latency_ms: hl.empty? ? 0 : (hl.sum / hl.size).round(2),
        errors: info[:errors]
      }
    end.sort_by { |h| -h[:count] }.first(10)

    {
      total_requests: total,
      avg_latency_ms: avg.round(2),
      error_count: snapshot[:errors],
      error_rate: total.zero? ? '0.0%' : format('%.1f%%', snapshot[:errors].to_f / total * 100),
      tracked_hosts: snapshot[:hosts].size,
      tracker_active: defined?(::Net::HTTP) && ::Net::HTTP.include?(OutboundHttpTracker),
      top_hosts: top_hosts
    }
  rescue => e
    { error: e.message }
  end
end
