require 'time'
require 'thread'

module DebugAgent
  MAX_ERRORS = 50
  @error_buffer = []
  @error_buffer_lock = Mutex.new

  class << self
    attr_reader :error_buffer

    def record_error(error, context = {})
      @error_buffer_lock.synchronize do
        @error_buffer << {
          timestamp: Time.now.iso8601,
          class: error.class.name,
          message: error.message,
          backtrace: (error.backtrace || []).first(10),
          context: context
        }
        @error_buffer.shift if @error_buffer.size > MAX_ERRORS
      end
    end
  end

  # Capture unhandled exceptions at process exit
  at_exit do
    if $!
      DebugAgent.record_error($!)
    end
  end

  register_tool('get_recent_errors',
                'Get recent unhandled exceptions captured by the agent (ring buffer, max 50). ' \
                'Each entry: timestamp, class, message, backtrace',
                limit: { type: 'integer', description: 'Maximum number of errors to return (default 20)', required: false }) do |limit: 20|
    errors = @error_buffer_lock.synchronize { @error_buffer.dup }

    if errors.empty?
      next {
        message: 'No errors captured yet. Errors are recorded via at_exit and when ' \
                 'DebugAgent.record_error is called (e.g. from a Sinatra error handler).',
        total: 0
      }
    end

    limit = limit.to_i
    limit = 20 if limit <= 0

    { total: errors.size, errors: errors.reverse.first(limit) }
  rescue => e
    { error: e.message }
  end

  register_tool('get_error_stats',
                'Get error statistics: total errors, rate per minute, and top error types') do
    errors = @error_buffer_lock.synchronize { @error_buffer.dup }

    if errors.empty?
      next { total: 0, message: 'No errors captured yet.' }
    end

    # Group by error class
    by_class = errors.group_by { |e| e[:class] }
    top_types = by_class.map do |klass, entries|
      { class: klass, count: entries.size, last_seen: entries.last[:timestamp] }
    end.sort_by { |t| -t[:count] }

    # Calculate rate per minute (errors in the last 60 seconds)
    now = Time.now
    recent = errors.select do |e|
      begin
        (now - Time.iso8601(e[:timestamp])) <= 60
      rescue
        false
      end
    end

    {
      total: errors.size,
      buffer_capacity: MAX_ERRORS,
      rate_per_minute: recent.size,
      unique_error_types: by_class.size,
      top_error_types: top_types.first(10),
      first_error: errors.first[:timestamp],
      last_error: errors.last[:timestamp]
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_error_patterns',
                'Group captured errors by exception class to identify recurring patterns') do
    errors = @error_buffer_lock.synchronize { @error_buffer.dup }

    if errors.empty?
      next { total: 0, message: 'No errors captured yet.' }
    end

    patterns = errors.group_by { |e| e[:class] }.map do |klass, entries|
      sample_messages = entries.map { |e| e[:message] }.uniq.first(5)
      {
        class: klass,
        count: entries.size,
        sample_messages: sample_messages,
        first_seen: entries.first[:timestamp],
        last_seen: entries.last[:timestamp],
        sample_backtrace: entries.last[:backtrace]
      }
    end.sort_by { |p| -p[:count] }

    {
      total_errors: errors.size,
      unique_patterns: patterns.size,
      patterns: patterns
    }
  rescue => e
    { error: e.message }
  end
end
