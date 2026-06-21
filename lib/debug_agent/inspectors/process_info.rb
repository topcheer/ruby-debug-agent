require 'etc'

module DebugAgent
  register_tool('get_process_info',
                'Get process info: PID, PPID, platform, Ruby version, uptime') do
    rss = `ps -o rss= -p #{Process.pid}`.to_i
    start_time = DebugAgent::PROCESS_START_TIME
    uptime_seconds = Time.now - start_time

    {
      pid: Process.pid,
      ppid: Process.ppid,
      uid: Process.uid,
      gid: Process.gid,
      user: Etc.getpwuid(Process.uid)&.name,
      platform: RUBY_PLATFORM,
      ruby_version: RUBY_VERSION,
      ruby_engine: RUBY_ENGINE,
      ruby_patchlevel: defined?(RUBY_PATCHLEVEL) ? RUBY_PATCHLEVEL : nil,
      ruby_revision: defined?(RUBY_REVISION) ? RUBY_REVISION.to_s : nil,
      process_name: $0,
      rss_mb: (rss / 1024.0).round(2),
      uptime_seconds: uptime_seconds.round(0),
      uptime_human: format_uptime(uptime_seconds),
      hostname: Socket.gethostname,
      cpu_count: Etc.nprocessors
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_cpu_time',
                'Get CPU time: user, system, and total (Process.times)') do
    times = Process.times
    {
      user_cpu_seconds: times.utime.round(4),
      system_cpu_seconds: times.stime.round(4),
      total_cpu_seconds: (times.utime + times.stime).round(4),
      child_user_cpu_seconds: times.cutime.round(4),
      child_system_cpu_seconds: times.cstime.round(4),
      child_total_cpu_seconds: (times.cutime + times.cstime).round(4)
    }
  rescue => e
    { error: e.message }
  end

  # Helper method for formatting uptime
  def self.format_uptime(seconds)
    days = (seconds / 86400).to_i
    hours = ((seconds % 86400) / 3600).to_i
    minutes = ((seconds % 3600) / 60).to_i
    secs = (seconds % 60).to_i

    parts = []
    parts << "#{days}d" if days > 0
    parts << "#{hours}h" if hours > 0 || days > 0
    parts << "#{minutes}m" if minutes > 0 || hours > 0 || days > 0
    parts << "#{secs}s"
    parts.join(' ')
  end
end
