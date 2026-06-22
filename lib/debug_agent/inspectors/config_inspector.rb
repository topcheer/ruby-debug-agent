require 'time'

module DebugAgent
  # Register configuration hashes for inspection.
  #
  #   DebugAgent.register_config(:app, {
  #     app_name: 'MyApp',
  #     port: 4567,
  #     api_key: 'secret123'
  #   })
  @registered_configs = {}

  SENSITIVE_KEY_PATTERN = /password|secret|token|api.?key|private.?key|credential/i

  class << self
    attr_reader :registered_configs

    def register_config(name, config_hash, source: 'registered')
      @registered_configs[name.to_s] = {
        values: config_hash,
        source: source,
        registered_at: Time.now.iso8601
      }
    end
  end

  class << self
    private

    def mask_sensitive(key, value)
      return value unless value.is_a?(String) || value.is_a?(Symbol)
      return '***' if key.to_s =~ SENSITIVE_KEY_PATTERN
      value
    end

    def mask_config_hash(hash)
      hash.map do |k, v|
        if v.is_a?(Hash)
          [k, mask_config_hash(v)]
        else
          [k, mask_sensitive(k, v)]
        end
      end.to_h
    end
  end

  register_tool('get_config_snapshot',
                'Get all registered configuration values. Sensitive keys (password, secret, ' \
                'token, api_key, etc.) are automatically masked') do
    if registered_configs.empty?
      next { error: 'No configs registered. Call DebugAgent.register_config(:name, hash).' }
    end

    configs = registered_configs.map do |name, entry|
      {
        name: name,
        source: entry[:source],
        registered_at: entry[:registered_at],
        values: mask_config_hash(entry[:values] || {}),
        key_count: (entry[:values] || {}).size,
        masked_keys: (entry[:values] || {}).keys.select { |k| k.to_s =~ SENSITIVE_KEY_PATTERN }
      }
    end

    {
      total_configs: configs.size,
      configs: configs
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_env_vars',
                'Dump environment variables (ENV) with optional prefix filter. ' \
                'Sensitive values are automatically masked',
                prefix: { type: 'string', description: 'Only return vars starting with this prefix (e.g. APP_, RAILS_)', required: false }) do |prefix: nil|
    vars = ENV.to_h

    if prefix && !prefix.to_s.empty?
      vars = vars.select { |k, _| k.start_with?(prefix.to_s) }
    end

    masked = {}
    sensitive_count = 0
    vars.each do |k, v|
      if k =~ SENSITIVE_KEY_PATTERN
        masked[k] = '***'
        sensitive_count += 1
      else
        masked[k] = v
      end
    end

    {
      total_vars: masked.size,
      sensitive_masked: sensitive_count,
      prefix_filter: prefix,
      env_vars: masked
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_config_sources',
                'Configuration provenance: shows where each registered config comes from ' \
                '(environment, file, default, or registered)') do
    if registered_configs.empty?
      next { error: 'No configs registered. Call DebugAgent.register_config(:name, hash).' }
    end

    sources = registered_configs.map do |name, entry|
      {
        name: name,
        source: entry[:source],
        registered_at: entry[:registered_at],
        keys: (entry[:values] || {}).keys
      }
    end

    # Also show ENV as a config source
    env_config_count = ENV.size

    {
      registered_config_sources: sources,
      total_sources: sources.size,
      env_var_count: env_config_count,
      summary: {
        registered: sources.count { |s| s[:source] == 'registered' },
        file: sources.count { |s| s[:source] == 'file' },
        env: sources.count { |s| s[:source] == 'env' },
        default: sources.count { |s| s[:source] == 'default' }
      }
    }
  rescue => e
    { error: e.message }
  end
end
