require 'time'

module DebugAgent
  # Register feature flags for inspection.
  #
  #   DebugAgent.register_feature_flag(:new_ui, enabled: true, variant: 'v2')
  @feature_flags = {}

  class << self
    attr_reader :feature_flags

    def register_feature_flag(name, enabled:, variant: nil)
      @feature_flags[name.to_s] = {
        enabled: enabled,
        variant: variant,
        registered_at: Time.now.iso8601
      }
    end
  end

  class << self
    private

    def flipper_flags
      return nil unless defined?(::Flipper)
      begin
        flipper = if ::Flipper.respond_to?(:instance)
                    ::Flipper.instance
                  elsif defined?(::Flipper::DSL)
                    ::Flipper
                  end
        return nil unless flipper

        flags = []
        flipper.features.each do |feature|
          state = feature.state
          flags << {
            name: feature.key,
            enabled: state == :on,
            variant: feature.enabled? ? 'enabled' : 'disabled',
            source: 'flipper'
          }
        end
        flags
      rescue
        nil
      end
    end

    def rollout_flags
      return nil unless defined?(::Rollout)
      begin
        r = if defined?($rollout)
              $rollout
            elsif ::Rollout.respond_to?(:instance)
              ::Rollout.instance
            end
        return nil unless r

        # Rollout stores features internally
        flags = []
        if r.respond_to?(:features)
          r.features.each do |name|
            flags << {
              name: name.to_s,
              enabled: r.active?(name),
              variant: nil,
              source: 'rollout'
            }
          end
        end
        flags
      rescue
        nil
      end
    end
  end

  register_tool('get_feature_flags',
                'List all feature flags (registered + auto-detected Flipper/Rollout). ' \
                'Shows name, enabled state, and variant') do
    flags = []

    # Registered flags
    feature_flags.each do |name, data|
      flags << {
        name: name,
        enabled: data[:enabled],
        variant: data[:variant],
        source: 'registered',
        registered_at: data[:registered_at]
      }
    end

    # Flipper detection
    flipper = flipper_flags
    if flipper
      existing = flags.map { |f| f[:name] }
      flipper.each do |f|
        flags << f unless existing.include?(f[:name])
      end
    end

    # Rollout detection
    rollout = rollout_flags
    if rollout
      existing = flags.map { |f| f[:name] }
      rollout.each do |f|
        flags << f unless existing.include?(f[:name])
      end
    end

    {
      total_flags: flags.size,
      enabled_count: flags.count { |f| f[:enabled] },
      disabled_count: flags.count { |f| !f[:enabled] },
      flags: flags,
      detected_providers: {
        flipper: defined?(::Flipper),
        rollout: defined?(::Rollout)
      }
    }
  rescue => e
    { error: e.message }
  end

  register_tool('evaluate_flag',
                'Evaluate a feature flag for a given context/user. Returns enabled state ' \
                'and variant for the specified flag',
                flag_name: { type: 'string', description: 'Name of the feature flag to evaluate', required: true },
                user_context: { type: 'string', description: 'User/context identifier for targeted flag evaluation (optional)', required: false }) do |flag_name:, user_context: nil|
    # Check registered flags first
    reg = feature_flags[flag_name.to_s]
    if reg
      result = {
        flag_name: flag_name,
        enabled: reg[:enabled],
        variant: reg[:variant],
        source: 'registered'
      }

      # Context-aware evaluation for Flipper/Rollout
      if user_context && defined?(::Flipper)
        begin
          flipper = ::Flipper.instance rescue ::Flipper
          feature = flipper[flag_name.to_sym]
          result[:flipper_enabled_for_user] = feature.enabled?(user_context)
          result[:flipper_source] = 'flipper'
        rescue
          nil
        end
      end

      if user_context && defined?(::Rollout)
        begin
          r = $rollout || (::Rollout.instance rescue nil)
          if r
            result[:rollout_active_for_user] = r.active?(flag_name.to_sym, user_context)
            result[:rollout_source] = 'rollout'
          end
        rescue
          nil
        end
      end

      next result
    end

    # Try Flipper
    if defined?(::Flipper)
      begin
        flipper = ::Flipper.instance rescue ::Flipper
        feature = flipper[flag_name.to_sym]
        next {
          flag_name: flag_name,
          enabled: feature.enabled?,
          variant: nil,
          source: 'flipper',
          user_context: user_context,
          enabled_for_user: user_context ? feature.enabled?(user_context) : nil
        }
      rescue
        nil
      end
    end

    # Try Rollout
    if defined?(::Rollout)
      begin
        r = $rollout || (::Rollout.instance rescue nil)
        if r
          next {
            flag_name: flag_name,
            enabled: r.active?(flag_name.to_sym),
            variant: nil,
            source: 'rollout',
            user_context: user_context,
            enabled_for_user: user_context ? r.active?(flag_name.to_sym, user_context) : nil
          }
        end
      rescue
        nil
      end
    end

    {
      flag_name: flag_name,
      enabled: false,
      source: 'not_found',
      error: "Flag '#{flag_name}' not found in registered flags, Flipper, or Rollout"
    }
  rescue => e
    { error: e.message }
  end
end
