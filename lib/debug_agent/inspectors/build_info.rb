require 'socket'
require 'etc'

module DebugAgent
  register_tool('get_build_info',
                'Get Ruby build info: version, engine (MRI/JRuby/TruffleRuby), ' \
                'platform, build date, RUBY_DESCRIPTION') do
    {
      ruby_version: RUBY_VERSION,
      ruby_engine: RUBY_ENGINE,
      ruby_engine_version: defined?(RUBY_ENGINE_VERSION) ? RUBY_ENGINE_VERSION : RUBY_VERSION,
      platform: RUBY_PLATFORM,
      ruby_description: RUBY_DESCRIPTION,
      ruby_patchlevel: defined?(RUBY_PATCHLEVEL) ? RUBY_PATCHLEVEL : nil,
      ruby_revision: defined?(RUBY_REVISION) ? RUBY_REVISION.to_s : nil,
      ruby_release_date: defined?(RUBY_RELEASE_DATE) ? RUBY_RELEASE_DATE : nil,
      build_date: defined?(RUBY_RELEASE_DATE) ? RUBY_RELEASE_DATE : nil,
      host_os: RbConfig::CONFIG['host_os'],
      host_cpu: RbConfig::CONFIG['host_cpu'],
      configure_args: RbConfig::CONFIG['configure_args']
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_deployment_info',
                'Get deployment info: hostname, PID, uptime, container detection, ' \
                'APP_ENV, Rails env') do
    rss = `ps -o rss= -p #{Process.pid}`.to_i
    uptime_seconds = Time.now - DebugAgent::PROCESS_START_TIME

    container_detected = File.exist?('/.dockerenv')
    in_cgroup = false
    begin
      in_cgroup = File.read('/proc/1/cgroup').include?('docker') ||
                  File.read('/proc/1/cgroup').include?('containerd')
    rescue
    end

    {
      hostname: Socket.gethostname,
      pid: Process.pid,
      ppid: Process.ppid,
      process_name: $0,
      uptime_seconds: uptime_seconds.round(0),
      rss_mb: (rss / 1024.0).round(2),
      container_detected: container_detected || in_cgroup,
      docker_detected: File.exist?('/.dockerenv'),
      app_env: ENV['APP_ENV'] || ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'unknown',
      rails_env: defined?(::Rails) ? ::Rails.env.to_s : nil,
      user: Etc.getpwuid(Process.uid)&.name,
      uid: Process.uid,
      gid: Process.gid,
      cpu_count: Etc.nprocessors
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_runtime_versions',
                'Get versions of key gems: rails, sinatra, sidekiq, redis, puma ' \
                'if loaded') do
    key_gems = %w[rails sinatra sidekiq redis puma rack rack-attack \
                  activerecord activesupport postgresql pg mysql2 bunny \
                  faraday httplog oj msgpack json]

    versions = {}
    key_gems.each do |gem_name|
      spec = Gem.loaded_specs[gem_name] || Gem.loaded_specs.values.find { |s| s.name == gem_name }
      versions[gem_name] = spec&.version&.to_s if spec
    end

    # Remove nils
    versions.compact!

    {
      ruby_version: RUBY_VERSION,
      ruby_engine: RUBY_ENGINE,
      rubygems_version: Gem::VERSION,
      bundler_version: defined?(Bundler) ? Bundler::VERSION : nil,
      loaded_gem_count: Gem.loaded_specs.size,
      key_gem_versions: versions
    }
  rescue => e
    { error: e.message }
  end
end
