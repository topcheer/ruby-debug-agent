require 'time'
require 'thread'

module DebugAgent
  # Registry of WebSocket servers (faye-websocket, websocket-driver, ActionCable).
  # Applications register WS server objects so the inspector can introspect them.
  #
  #   DebugAgent.register_ws_server(:faye, ws_server)
  @ws_servers = {}
  @ws_connections = []
  @ws_lock = Mutex.new
  @ws_message_log = []

  class << self
    attr_reader :ws_servers, :ws_connections, :ws_message_log

    def register_ws_server(name, server)
      @ws_servers[name.to_s] = server
    end

    # Track a WebSocket connection
    def track_ws_connection(conn_id, remote_addr, channel = nil)
      @ws_lock.synchronize do
        @ws_connections << {
          id: conn_id,
          remote_addr: remote_addr,
          channel: channel,
          connected_since: Time.now.iso8601,
          messages_sent: 0,
          messages_received: 0
        }
      end
      conn_id
    end

    # Remove a tracked WebSocket connection
    def untrack_ws_connection(conn_id)
      @ws_lock.synchronize do
        @ws_connections.reject! { |c| c[:id] == conn_id }
      end
    end

    # Log a WebSocket message
    def log_ws_message(conn_id, direction, data, size = nil)
      @ws_lock.synchronize do
        @ws_message_log << {
          timestamp: Time.now.iso8601,
          connection_id: conn_id,
          direction: direction, # 'sent' or 'received'
          size: size || data.to_s.bytesize,
          preview: data.to_s[0...200]
        }
        @ws_message_log.shift if @ws_message_log.size > 200

        conn = @ws_connections.find { |c| c[:id] == conn_id }
        if conn
          if direction == 'sent'
            conn[:messages_sent] += 1
          else
            conn[:messages_received] += 1
          end
        end
      end
    end
  end

  register_tool('get_ws_connections',
                'Get active WebSocket connections (faye-websocket, websocket-driver, ActionCable). ' \
                'Shows connection ID, remote address, connected since, and message counts') do
    conns = @ws_lock.synchronize { @ws_connections.dup }

    # Also try to auto-detect ActionCable connections
    if defined?(::ActionCable)
      begin
        server = ::ActionCable.server
        if server && server.respond_to?(:connections)
          server.connections.each do |conn|
            next if conns.any? { |c| c[:id] == conn.object_id }
            conns << {
              id: conn.object_id,
              remote_addr: conn.respond_to?(:env) ? (conn.env['REMOTE_ADDR'] rescue 'unknown') : 'unknown',
              channel: 'ActionCable',
              connected_since: nil,
              messages_sent: conn.respond_to?(:transmissions) ? conn.transmissions : nil,
              messages_received: nil,
              source: 'actioncable'
            }
          end
        end
      rescue => e
        conns << { source: 'actioncable', error: e.message }
      end
    end

    if conns.empty?
      next {
        message: 'No WebSocket connections tracked. Register with DebugAgent.register_ws_server ' \
                 'or DebugAgent.track_ws_connection. Auto-detects ActionCable if loaded.',
        total: 0
      }
    end

    { total: conns.size, connections: conns }
  rescue => e
    { error: e.message }
  end

  register_tool('get_ws_stats',
                'Get WebSocket statistics: total connections, total messages, ' \
                'messages per connection, uptime') do
    conns = @ws_lock.synchronize { @ws_connections.dup }
    msgs = @ws_lock.synchronize { @ws_message_log.dup }

    if conns.empty? && msgs.empty?
      next { total_connections: 0, total_messages: 0, message: 'No WebSocket activity recorded.' }
    end

    sent = conns.sum { |c| c[:messages_sent] || 0 }
    received = conns.sum { |c| c[:messages_received] || 0 }
    total_bytes = msgs.sum { |m| m[:size] || 0 }

    {
      total_connections: conns.size,
      total_messages_sent: sent,
      total_messages_received: received,
      total_messages: sent + received,
      total_bytes: total_bytes,
      avg_messages_per_connection: conns.empty? ? 0 : ((sent + received).to_f / conns.size).round(2),
      registered_servers: ws_servers.keys,
      recent_messages: msgs.reverse.first(20)
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_ws_channels',
                'Get WebSocket channels with subscriber counts (ActionCable channels or custom pub/sub)') do
    channels = []

    # Auto-detect ActionCable channels
    if defined?(::ActionCable::Channel::Base)
      begin
        # Look for channel subclasses
        channel_classes = []
        ObjectSpace.each_object(Class) do |klass|
          if klass < ::ActionCable::Channel::Base && klass != ::ActionCable::Channel::Base
            channel_classes << klass
          end
        end

        channel_classes.uniq.each do |klass|
          channels << {
            name: klass.name,
            source: 'actioncable',
            subscribers: 0 # ActionCable doesn't expose per-channel counts easily
          }
        end
      rescue => e
        channels << { source: 'actioncable', error: e.message }
      end
    end

    # Track connections grouped by channel from our own registry
    @ws_lock.synchronize do
      by_channel = @ws_connections.group_by { |c| c[:channel] || 'default' }
      by_channel.each do |channel, conns|
        existing = channels.find { |ch| ch[:name] == channel }
        if existing
          existing[:subscribers] = conns.size
        else
          channels << { name: channel, source: 'tracked', subscribers: conns.size }
        end
      end
    end

    if channels.empty?
      next {
        message: 'No WebSocket channels found. Define ActionCable channels or use ' \
                 'DebugAgent.track_ws_connection with a channel name.',
        total: 0
      }
    end

    { total: channels.size, channels: channels }
  rescue => e
    { error: e.message }
  end
end
