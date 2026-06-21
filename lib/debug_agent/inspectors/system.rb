require 'etc'

module DebugAgent
  register_tool('get_system_info', 'Get system info: hostname, CPU, memory, load') do
    {
      hostname: Socket.gethostname,
      os: RUBY_PLATFORM,
      cpu_count: Etc.nprocessors,
      ruby_version: RUBY_VERSION,
      process_count: `ps aux | wc -l`.strip.to_i
    }
  end

  register_tool('get_disk_usage', 'Get disk usage for current directory') do
    stat = Sys::Filesystem.stat(Dir.pwd) rescue nil
    if stat
      {
        total_gb: (stat.block_size * stat.blocks / 1024**3).round(2),
        free_gb: (stat.block_size * stat.blocks_available / 1024**3).round(2),
        used_pct: ((1 - stat.blocks_available.to_f / stat.blocks) * 100).round(1)
      }
    else
      # Fallback: use df
      output = `df -k .`.split("\n").last.split
      total = output[1].to_i / 1024 / 1024.0
      free = output[3].to_i / 1024 / 1024.0
      {
        total_gb: total.round(2),
        free_gb: free.round(2),
        used_pct: output[4]
      }
    end
  end

  register_tool('get_environment_variables', 'List environment variables (masked secrets)') do |prefix: ''|
    secret_patterns = %w[KEY SECRET PASSWORD TOKEN CREDENTIAL]
    result = {}
    ENV.each do |k, v|
      next if !prefix.empty? && !k.upcase.start_with?(prefix.upcase)

      if secret_patterns.any? { |s| k.upcase.include?(s) }
        result[k] = '***masked***'
      else
        result[k] = v
      end
    end
    { variables: result, count: result.size }
  end

  register_tool('get_process_info', 'Get process info: PID, CPU time, user') do
    rss = `ps -o rss= -p #{Process.pid}`.to_i
    {
      pid: Process.pid,
      ppid: Process.ppid,
      rss_mb: (rss / 1024.0).round(2),
      uid: Process.uid,
      gid: Process.gid,
      user: Etc.getpwuid(Process.uid).name
    }
  end
end
