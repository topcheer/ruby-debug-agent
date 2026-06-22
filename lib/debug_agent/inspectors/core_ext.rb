module DebugAgent
  register_tool('get_fiber_info',
                'List alive fibers (Ruby 3.0+ via Fiber.list) with status and backtrace') do
    unless Fiber.respond_to?(:list)
      return {
        supported: false,
        message: 'Fiber.list requires Ruby 3.0+. ' \
          "Current Ruby: #{RUBY_VERSION} (#{RUBY_ENGINE})"
      }
    end

    fibers = Fiber.list.map do |fiber|
      backtrace =
        begin
          fiber.backtrace || []
        rescue => e
          ["<unable to get backtrace: #{e.message}>"]
        end

      {
        object_id: fiber.object_id,
        to_s: fiber.to_s,
        alive: fiber.alive?,
        resizable: fiber.respond_to?(:resizable?) ? fiber.resizable? : nil,
        storage: fiber.respond_to?(:storage) ? (fiber.storage&.keys&.map(&:to_s) rescue nil) : nil,
        backtrace_summary: backtrace.first(5),
        backtrace_length: backtrace.size
      }
    end

    {
      supported: true,
      total_fibers: fibers.size,
      alive_fibers: fibers.count { |f| f[:alive] },
      fibers: fibers
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_signal_handlers',
                'List registered signal handlers (Signal.trap) and default handlers') do
    handlers = []

    Signal.list.each do |name, number|
      begin
        current = Signal.trap(name)
      rescue => e
        current = "<error: #{e.message}>"
      end

      handlers << {
        signal: name,
        number: number,
        handler:
          case current
          when 'DEFAULT' then 'DEFAULT (system default)'
          when 'IGNORE'  then 'IGNORE (ignored)'
          when 'EXIT'    then 'EXIT (terminate process)'
          when 'SYSTEM_DEFAULT' then 'SYSTEM_DEFAULT'
          when String then current
          when Proc
            begin
              src = current.source_location
              src ? "Proc at #{src.join(':')}" : 'Proc (unknown source)'
            rescue
              'Proc'
            end
          else
            current.inspect
          end
      }
    end

    {
      total_signals: handlers.size,
      signals: handlers.sort_by { |h| h[:number] }
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_encoding_info',
                'Get Ruby encoding info: Encoding.list, default external/internal/locale encodings') do
    list = Encoding.list.map do |enc|
      {
        name: enc.name,
        aliases: Encoding.aliases.select { |_, n| n == enc.name }.keys,
        dummy: enc.dummy?,
        ascii_compatible: enc.ascii_compatible?
      }
    end

    {
      total_encodings: list.size,
      default_external: Encoding.default_external.to_s,
      default_internal: Encoding.default_internal&.to_s,
      locale: Encoding.find('locale').to_s,
      filesystem: Encoding.find('filesystem').to_s,
      encodings: list
    }
  rescue => e
    { error: e.message }
  end
end
