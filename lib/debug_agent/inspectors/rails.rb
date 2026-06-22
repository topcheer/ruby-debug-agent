module DebugAgent
  register_tool('get_rails_routes',
                'List all Rails routes: verb, path, controller#action ' \
                '(requires Rails.application.routes)') do
    unless defined?(::Rails) && defined?(::ActionDispatch)
      return { error: 'Rails is not loaded (Rails::Application not found)' }
    end

    routes_set = ::Rails.application.routes.routes

    routes = routes_set.map do |route|
      {
        name: route.name,
        verb: route.verb.source.gsub(/[$^]/, ''),
        path: route.path.spec.to_s,
        controller: route.defaults[:controller]&.to_s,
        action: route.defaults[:action]&.to_s,
        internal: route.internal?
      }
    end

    {
      total: routes.size,
      routes: routes
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_rails_models',
                'List ActiveRecord models: class name, table name, columns ' \
                '(iterates ActiveRecord::Base.descendants)') do
    unless defined?(::ActiveRecord)
      return { error: 'ActiveRecord is not loaded (ActiveRecord::Base not found)' }
    end

    models = ::ActiveRecord::Base.descendants.map do |model|
      columns =
        begin
          if model.table_exists?
            model.columns.map do |col|
              {
                name: col.name,
                type: col.sql_type_metadata&.type.to_s,
                sql_type: col.sql_type_metadata&.sql_type.to_s,
                null: col.null,
                default: col.default,
                primary: col.name == model.primary_key
              }
            end
          else
            []
          end
        rescue => e
          [{ error: e.message }]
        end

      table_name = begin
        model.table_name
      rescue
        nil
      end

      table_exists = begin
        model.table_exists?
      rescue
        false
      end

      {
        class_name: model.name,
        table_name: table_name,
        table_exists: table_exists,
        column_count: columns.size,
        columns: columns
      }
    end

    {
      total: models.size,
      models: models.sort_by { |m| m[:class_name].to_s }
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_rails_schema',
                'Get ActiveRecord schema cache: table names and column definitions ' \
                '(uses ActiveRecord::Base.connection.tables)') do
    unless defined?(::ActiveRecord)
      return { error: 'ActiveRecord is not loaded (ActiveRecord::Base not found)' }
    end

    connection = ::ActiveRecord::Base.connection
    tables = connection.tables

    schema = tables.map do |table|
      columns =
        begin
          connection.columns(table).map do |col|
            {
              name: col.name,
              type: col.sql_type_metadata&.type.to_s,
              sql_type: col.sql_type_metadata&.sql_type.to_s,
              null: col.null,
              default: col.default
            }
          end
        rescue => e
          [{ error: e.message }]
        end

      {
        table: table,
        column_count: columns.size,
        columns: columns
      }
    end

    {
      total_tables: schema.size,
      tables: schema
    }
  rescue => e
    { error: e.message }
  end
end
