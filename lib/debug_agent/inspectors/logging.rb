require 'time'
require 'thread'
require 'logger'

module DebugAgent
  # Ring buffer of recent log entries and a registry of named loggers.
  #
  #   DebugAgent.register_logger(:app, Rails.logger)
  MAX_LOGS = 100

  @log_buffer = []
  @log_buffer_lock = Mutex.new
  @loggers = {}

  class << self
    attr_reader :loggers

    def register_logger(name, logger)
      @loggers[name.to_s] = logger
    end

    # Invoked by the wrapped Logger#add to push an entry into the ring buffer.
    def capture_log(severity, args)
      args = args.is_a?(Array) ? args : [args]
      # Logger passes (message, progname); pick the meaningful value.
      msg = args.compact.first
      entry = {
        timestamp: Time.now.iso8601,
        severity: severity_label(severity),
        message: msg.respond_to?(:to_str) ? msg.to_s : msg.inspect
      }
      @log_buffer_lock.synchronize do
        @log_buffer << entry
        @log_buffer.shift if @log_buffer.size > MAX_LOGS
      end
    end

    # Wrap the standard Logger#add / << so all log output flows into the ring
    # buffer. Only wraps once — guarded by checking for the aliased method.
    def install_log_capture
      return false unless defined?(::Logger)
      return true if ::Logger.method_defined?(:_original_add)

      ::Logger.class_eval do
        alias_method :_original_add, :add
        alias_method :_original_lshift, :<<

        def add(severity, *args, &block)
          if block
            msg = args[0]
            msg = block.call if msg.nil?
            DebugAgent.capture_log(severity, [msg]) rescue nil
            _original_add(severity, msg, *args[1..-1])
          else
            DebugAgent.capture_log(severity, args) rescue nil
            _original_add(severity, *args)
          end
        end

        def <<(msg)
          DebugAgent.capture_log(nil, [msg]) rescue nil
          _original_lshift(msg)
        end
      end
      true
    end

    # Map a Logger severity integer to a human-readable label.
    def severity_label(severity)
      labels = %w[DEBUG INFO WARN ERROR FATAL ANY]
      idx = severity.is_a?(Integer) ? severity : (defined?(::Logger) ? ::Logger::UNKNOWN : 5)
      labels[idx] || 'UNKNOWN'
    end
  end

  # Attempt to wrap Logger at load time (no-op if Logger isn't loaded yet).
  install_log_capture

  LEVEL_MAP = {
    'debug' => defined?(::Logger) ? ::Logger::DEBUG : 0,
    'info'  => defined?(::Logger) ? ::Logger::INFO  : 1,
    'warn'  => defined?(::Logger) ? ::Logger::WARN  : 2,
    'error' => defined?(::Logger) ? ::Logger::ERROR : 3,
    'fatal' => defined?(::Logger) ? ::Logger::FATAL : 4
  }.freeze

  register_tool('get_log_buffer',
                'Return recent log entries captured from the built-in ring buffer ' \
                '(Logger#add and << are auto-wrapped)') do |limit: 50|
    limit = limit.to_i
    limit = 50 if limit <= 0
    entries = @log_buffer_lock.synchronize { @log_buffer.dup }
    {
      total_captured: entries.size,
      capacity: MAX_LOGS,
      capture_active: defined?(::Logger) && ::Logger.method_defined?(:_original_add),
      entries: entries.last(limit).reverse
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_logger_info',
                'List registered loggers with configuration: level, device, formatter, progname') do
    if loggers.empty?
      next {
        message: 'No loggers registered. Call DebugAgent.register_logger(:name, logger).',
        capture_active: defined?(::Logger) && ::Logger.method_defined?(:_original_add)
      }
    end

    list = loggers.map do |name, logger|
      info = { name: name, class: logger.class.name }
      info[:level] = severity_label(logger.level) if logger.respond_to?(:level)
      info[:progname] = logger.progname if logger.respond_to?(:progname)

      if defined?(::Logger) && logger.is_a?(::Logger)
        logdev = logger.instance_variable_get(:@logdev)
        dev = logdev&.instance_variable_get(:@dev)
        info[:device] =
          case dev
          when IO then dev.inspect
          when String then dev
          when nil then nil
          else dev.inspect
          end
        formatter = logger.instance_variable_get(:@formatter)
        info[:formatter] = formatter ? formatter.class.name : 'default'
      end
      info
    rescue => e
      { name: name, error: e.message }
    end

    { loggers: list }
  rescue => e
    { error: e.message }
  end

  register_tool('set_log_level',
                "Dynamically change a registered logger's level",
                logger_name: { type: 'string', description: 'Registered logger name' },
                level: { type: 'string', description: 'One of: debug, info, warn, error, fatal' }) do |logger_name:, level:|
    logger = loggers[logger_name.to_s]
    next({ error: "No logger registered under '#{logger_name}'" }) unless logger
    next({ error: 'Logger does not respond to level=' }) unless logger.respond_to?(:level=)

    target = LEVEL_MAP[level.to_s.downcase]
    next({ error: "Invalid level '#{level}'. Use debug/info/warn/error/fatal." }) unless target

    previous = severity_label(logger.level)
    logger.level = target

    {
      logger: logger_name,
      previous_level: previous,
      new_level: level.to_s.downcase,
      success: true
    }
  rescue => e
    { error: e.message }
  end
end
