require 'time'

module DebugAgent
  # Track database migration status.
  #
  # Auto-detects ActiveRecord::SchemaMigration if loaded.
  # Custom providers can be registered:
  #
  #   DebugAgent.register_migration_provider -> {
  #     {
  #       current_version: 3,
  #       pending: [{ version: 4, name: 'add_index' }],
  #       applied: [{ version: 1, name: 'create_users', applied_at: '...' }, ...]
  #     }
  #   }
  @migration_provider = nil

  class << self
    attr_accessor :migration_provider

    def register_migration_provider(fn)
      @migration_provider = fn
    end

    def migration_data
      # Custom provider takes precedence
      if @migration_provider
        result = @migration_provider.call
        return result if result.is_a?(Hash)
      end

      # ActiveRecord auto-detection
      if defined?(::ActiveRecord::SchemaMigration)
        return ar_migration_data
      end

      nil
    end

    private

    def ar_migration_data
      begin
        sm = ::ActiveRecord::SchemaMigration
        current = ::ActiveRecord::Migrator.current_version rescue sm.all_versions.map(&:to_i).max || 0

        # Get applied migrations
        applied = sm.all_versions.map(&:to_i).sort

        # Get pending from migration files
        pending = []
        if defined?(::ActiveRecord::Migration)
          migrations_dir = 'db/migrate/'
          if Dir.exist?(migrations_dir)
            file_versions = Dir.glob("#{migrations_dir}/*.rb").map do |f|
              File.basename(f).split('_').first.to_i
            end
            pending = (file_versions - applied).map do |v|
              { version: v, name: 'pending' }
            end
          end
        end

        {
          current_version: current,
          applied: applied.map { |v| { version: v } },
          pending: pending
        }
      rescue => e
        { error: "ActiveRecord migration query failed: #{e.message}" }
      end
    end
  end

  register_tool('get_migration_status',
                'Current database schema migration status: current version, total applied, ' \
                'total pending. Auto-detects ActiveRecord or uses registered provider') do
    data = migration_data

    if data.nil?
      next {
        error: 'No migration data available. Either load ActiveRecord or register a provider ' \
          'with DebugAgent.register_migration_provider(-> { ... })'
      }
    end

    next data if data[:error]

    {
      current_version: data[:current_version],
      applied_count: (data[:applied] || []).size,
      pending_count: (data[:pending] || []).size,
      source: if migration_provider
                'custom_provider'
              elsif defined?(::ActiveRecord::SchemaMigration)
                'active_record'
              else
                'unknown'
              end
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_pending_migrations',
                'List unapplied/pending database migrations that have not yet been run') do
    data = migration_data

    if data.nil?
      next {
        error: 'No migration data available. Either load ActiveRecord or register a provider.'
      }
    end

    next data if data[:error]

    pending = data[:pending] || []
    {
      pending_count: pending.size,
      migrations: pending,
      recommendation: pending.any? ?
                        'Run pending migrations before deploying.' :
                        'All migrations are up to date.'
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_migration_history',
                'Applied migration history log: versions and timestamps of all applied migrations') do
    data = migration_data

    if data.nil?
      next {
        error: 'No migration data available. Either load ActiveRecord or register a provider.'
      }
    end

    next data if data[:error]

    applied = data[:applied] || []
    {
      total_applied: applied.size,
      latest_version: applied.any? ? applied.last[:version] : 0,
      migrations: applied
    }
  rescue => e
    { error: e.message }
  end
end
