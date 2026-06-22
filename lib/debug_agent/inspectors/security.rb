module DebugAgent
  # Registry of auth configurations (Devise, Warden, OmniAuth, Rack auth).
  #
  #   DebugAgent.register_auth_config(:api_key, { strategy: 'X-API-Key', secret_present: true })
  @auth_configs = {}

  # Registry of session stores (Rack::Session, ActiveRecord::Session, custom).
  #
  #   DebugAgent.register_session_store(:rack_session, env['rack.session'])
  @session_stores = {}

  class << self
    attr_reader :auth_configs, :session_stores

    def register_auth_config(name, config)
      @auth_configs[name.to_s] = config
    end

    def register_session_store(name, store)
      @session_stores[name.to_s] = store
    end
  end

  register_tool('get_auth_config',
                'List registered auth configurations (Devise, Warden, OmniAuth, Rack auth). ' \
                'Shows strategy, whether a secret is present, and token expiry') do |name: nil|
    # Auto-detect from loaded gems when nothing is registered
    if auth_configs.empty?
      auto = {}
      if defined?(::Devise)
        auto['Devise'] = {
          strategy: 'Devise',
          secret_present: defined?(Devise.secret_key) && !Devise.secret_key.to_s.empty?,
          models: (Devise.mappings.keys.map(&:to_s) rescue []),
          token_expiry: nil
        }
      end
      if defined?(::Warden)
        auto['Warden'] = {
          strategy: 'Warden',
          secret_present: !!(Warden::Manager.respond_to?(:secret) rescue false),
          default_strategies: (Warden::Config.new.default_strategies rescue []),
          token_expiry: nil
        }
      end
      if defined?(::OmniAuth)
        auto['OmniAuth'] = {
          strategy: 'OmniAuth',
          providers: (OmniAuth.strategies.map(&:to_s) rescue []),
          secret_present: !!(OmniAuth.configuration rescue nil),
          token_expiry: nil
        }
      end
      if auto.any?
        next { auth_configs: auto, source: 'auto-detected' }
      end
      next { error: 'No auth configs registered. Call DebugAgent.register_auth_config(:name, config).' }
    end

    targets = name ? { name.to_s => auth_configs[name.to_s] } : auth_configs
    targets = targets.reject { |_, c| c.nil? }
    next { error: "No auth config registered under '#{name}'" } if targets.empty?

    results = targets.map do |cfg_name, cfg|
      begin
        if cfg.is_a?(Hash)
          normalized = {
            name: cfg_name,
            strategy: cfg[:strategy] || cfg['strategy'],
            secret_present: cfg.key?(:secret_present) ? cfg[:secret_present] : cfg['secret_present'],
            token_expiry: cfg[:token_expiry] || cfg['token_expiry']
          }.merge(cfg.reject { |k, _| %i[strategy secret_present token_expiry].include?(k.to_sym) })
          normalized
        else
          { name: cfg_name, type: cfg.class.name, raw: cfg.inspect }
        end
      rescue => e
        { name: cfg_name, error: e.message }
      end
    end

    { auth_configs: results }
  rescue => e
    { error: e.message }
  end

  register_tool('get_active_sessions',
                'List active sessions from registered session stores ' \
                '(Rack::Session, ActiveRecord::Session). ' \
                'Shows session ID, user, creation, and expiry') do |name: nil|
    if session_stores.empty?
      next { error: 'No session stores registered. Call DebugAgent.register_session_store(:name, store).' }
    end

    targets = name ? { name.to_s => session_stores[name.to_s] } : session_stores
    targets = targets.reject { |_, s| s.nil? }
    next { error: "No session store registered under '#{name}'" } if targets.empty?

    results = targets.map do |store_name, store|
      begin
        introspect_session_store(store_name, store)
      rescue => e
        { name: store_name, error: e.message }
      end
    end

    { session_stores: results }
  rescue => e
    { error: e.message }
  end

  register_tool('get_cors_config',
                'Show CORS settings (Rack::Cors config: allowed origins, methods, headers)') do
    # Try to find Rack::Cors middleware in the app middleware stack
    cors_rules = []

    if app && app.respond_to?(:middleware)
      app.middleware.each do |middleware_entry|
        middleware_class = middleware_entry.shift if middleware_entry.is_a?(Array)
        next unless middleware_class.to_s.include?('Cors')

        args = middleware_entry || []
        cors_rules << { middleware: middleware_class.to_s, args: args.inspect }
      end
    end

    # Try Rack::Cors introspection
    if defined?(::Rack::Cors)
      begin
        rack_cors = ::Rack::Cors
        cors_rules << { middleware: 'Rack::Cors', version: rack_cors.respond_to?(:VERSION) ? rack_cors::VERSION : 'unknown' }
      rescue => e
        cors_rules << { middleware: 'Rack::Cors', error: e.message }
      end
    end

    if cors_rules.empty?
      next {
        message: 'No CORS configuration detected. Install rack-cors and configure Rack::Cors middleware, ' \
                 'or the inspector could not find CORS rules in the middleware stack.',
        cors_enabled: false
      }
    end

    { cors_enabled: true, rules: cors_rules }
  rescue => e
    { error: e.message }
  end

  # --- Helpers ---

  def self.introspect_session_store(store_name, store)
    info = { name: store_name, type: store.class.name }

    # Rack::Session::Abstract::SessionHash or similar
    if store.respond_to?(:to_hash)
      begin
        data = store.to_hash
        info[:session_count] = data.size
        info[:keys] = data.keys.first(50)
        info[:has_user] = data.key?('user_id') || data.key?(:user_id) || data.key?('user')
      rescue
        info[:session_count] = 'unable to read'
      end
    end

    # ActiveRecord::SessionStore
    if store.respond_to?(:all)
      begin
        sessions = store.all.to_a
        info[:session_count] = sessions.size
        info[:sessions] = sessions.first(20).map do |sess|
          sess_data = begin
            sess.respond_to?(:data) ? sess.data.keys : []
          rescue
            []
          end
          {
            session_id: sess.respond_to?(:session_id) ? sess.session_id : sess.id,
            data: sess_data,
            created_at: sess.respond_to?(:created_at) ? sess.created_at : nil,
            updated_at: sess.respond_to?(:updated_at) ? sess.updated_at : nil
          }
        end
      rescue
        info[:session_count] = 'unable to read'
      end
    end

    # Generic session store with session_id method
    if store.respond_to?(:session_id)
      begin
        info[:session_id] = store.session_id
      rescue
        # ignore
      end
    end

    info
  end
end
