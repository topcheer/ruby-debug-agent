module DebugAgent
  register_tool('get_registered_services',
                'List all registered debug agent tools grouped by inspector category. ' \
                'Shows tool count and names per group.') do
    all_tools = registry.names

    # Categorize tools by known inspector groups
    categories = {
      'runtime' => %w[get_gc_stats get_memory_summary trigger_gc get_thread_summary get_runtime_info get_object_allocations],
      'gc' => %w[],
      'object_space' => %w[],
      'threads' => %w[],
      'process' => %w[],
      'system' => %w[],
      'http_tracker' => %w[],
      'routes' => %w[],
      'redis' => %w[],
      'rails' => %w[],
      'sidekiq' => %w[],
      'puma' => %w[],
      'logging' => %w[],
      'cache' => %w[],
      'http_client' => %w[],
      'metrics' => %w[],
      'active_record_stats' => %w[],
      'faraday' => %w[],
      'concurrent' => %w[],
      'security' => %w[],
      'health' => %w[],
      'scheduler' => %w[],
      'error_tracking' => %w[],
      'websocket' => %w[],
      'locks' => %w[],
      'migration' => %w[],
      'config' => %w[],
      'feature_flags' => %w[],
      'endpoint_test' => %w[],
      'pool_inspector' => %w[],
      'cpu_profile' => %w[],
      'leak_detector' => %w[],
      'build_info' => %w[],
      'snapshot' => %w[],
      'service_registry' => %w[]
    }

    # Since we cannot reliably categorize at runtime without a lookup table,
    # we list all tools alphabetically with their descriptions
    tools_with_desc = all_tools.sort.map do |name|
      tool = registry.get(name)
      {
        name: name,
        description: tool&.respond_to?(:description) ? tool.description : nil
      }
    end

    {
      total_tools: all_tools.size,
      tools: tools_with_desc
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_service_dependencies',
                'Show all loaded gems and their versions from Gem.loaded_specs') do
    specs = Gem.loaded_specs.values.sort_by(&:name)

    gems = specs.map do |spec|
      {
        name: spec.name,
        version: spec.version.to_s,
        loaded_from: spec.loaded_from,
        dependencies: spec.dependencies.map { |d| "#{d.name} (#{d.requirement})" }
      }
    end

    {
      total_gems: gems.size,
      ruby_version: RUBY_VERSION,
      ruby_engine: RUBY_ENGINE,
      rubygems_version: Gem::VERSION,
      bundler_version: defined?(Bundler) ? Bundler::VERSION : nil,
      gems: gems
    }
  rescue => e
    { error: e.message }
  end
end
