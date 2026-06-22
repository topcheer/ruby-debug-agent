# Demo: Order Management API with Ruby Debug Agent
# Run: ruby demo/app.rb
# Open: http://localhost:4567/agent
#
# Requires: gem install sinatra redis sidekiq sqlite3
#
# Optional services:
#   - Redis: caching + Sidekiq backend (falls back to in-memory if unavailable)
#   - Sidekiq: background job processing (runs inline if Redis unavailable)
#   - SQLite3: persistent order storage (required)

require_relative '../lib/debug_agent'

require 'sinatra/base'
require 'json'
require 'logger'
require 'time'

# ─── Optional: Redis ──────────────────────────────────────────────────────────

REDIS_URL = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')

redis_available = false
begin
  require 'redis'
  REDIS = Redis.new(url: REDIS_URL)
  REDIS.ping # connection test
  redis_available = true
  DebugAgent.register_redis_client(:cache, REDIS)
rescue LoadError
  REDIS = nil
  warn '[demo] redis gem not installed — running without Redis caching'
rescue => e
  REDIS = nil
  warn "[demo] Redis not reachable at #{REDIS_URL}: #{e.message}"
end

# ─── Optional: Sidekiq ────────────────────────────────────────────────────────

sidekiq_available = false
begin
  require 'sidekiq'

  Sidekiq.configure_server do |config|
    config.redis = { url: REDIS_URL }
  end
  Sidekiq.configure_client do |config|
    config.redis = { url: REDIS_URL }
  end

  sidekiq_available = true

  # Register the default queue with the inspector
  begin
    DebugAgent.register_sidekiq_queue(:default, Sidekiq::Queue.new('default'))
  rescue => e
    warn "[demo] Could not register Sidekiq queue: #{e.message}"
  end
rescue LoadError
  warn '[demo] sidekiq gem not installed — running without background jobs'
rescue => e
  warn "[demo] Sidekiq unavailable: #{e.message}"
end

# ─── SQLite3 Storage ──────────────────────────────────────────────────────────

require 'sqlite3'

DB_PATH = ENV.fetch('DB_PATH', File.expand_path('demo_orders.db', __dir__))

DB = SQLite3::Database.new(DB_PATH)
DB.results_as_hash = true
DB.results_as_hash = true

DB.execute(<<~SQL)
  CREATE TABLE IF NOT EXISTS orders (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    customer   TEXT    NOT NULL,
    item       TEXT    NOT NULL,
    quantity   INTEGER NOT NULL DEFAULT 1,
    price      REAL    NOT NULL DEFAULT 0.0,
    total      REAL    NOT NULL DEFAULT 0.0,
    status     TEXT    NOT NULL DEFAULT 'pending',
    created_at TEXT    NOT NULL,
    updated_at TEXT
  )
SQL

DB.execute(<<~SQL)
  CREATE TABLE IF NOT EXISTS order_events (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id   INTEGER,
    event      TEXT    NOT NULL,
    created_at TEXT    NOT NULL
  )
SQL

def db_order_from_row(row)
  {
    id: row['id'],
    customer: row['customer'],
    item: row['item'],
    quantity: row['quantity'],
    price: row['price'],
    total: row['total'],
    status: row['status'],
    created_at: row['created_at'],
    updated_at: row['updated_at']
  }
end

# ─── Background Worker ────────────────────────────────────────────────────────

if sidekiq_available && defined?(Sidekiq::Job)
  # Sidekiq 7.x (Sidekiq::Job)
  class ProcessOrderWorker
    include Sidekiq::Job

    def perform(order_id)
      LOGGER.info("[ProcessOrderWorker] Processing order ##{order_id}")
      sleep 0.2 # simulate work

      DB.execute(
        'UPDATE orders SET status = ?, updated_at = ? WHERE id = ?',
        ['processed', Time.now.iso8601, order_id]
      )
      DB.execute(
        'INSERT INTO order_events (order_id, event, created_at) VALUES (?, ?, ?)',
        [order_id, 'processed', Time.now.iso8601]
      )
      LOGGER.info("[ProcessOrderWorker] Order ##{order_id} marked as processed")
    end
  end
elsif sidekiq_available
  # Sidekiq 6.x (Sidekiq::Worker + sidekiq_options)
  class ProcessOrderWorker
    include Sidekiq::Worker

    sidekiq_options queue: 'default', retry: 3

    def perform(order_id)
      LOGGER.info("[ProcessOrderWorker] Processing order ##{order_id}")
      sleep 0.2 # simulate work

      DB.execute(
        'UPDATE orders SET status = ?, updated_at = ? WHERE id = ?',
        ['processed', Time.now.iso8601, order_id]
      )
      DB.execute(
        'INSERT INTO order_events (order_id, event, created_at) VALUES (?, ?, ?)',
        [order_id, 'processed', Time.now.iso8601]
      )
      LOGGER.info("[ProcessOrderWorker] Order ##{order_id} marked as processed")
    end
  end
else
  # Fallback: inline processing when Sidekiq is not installed
  class ProcessOrderWorker
    def self.perform_async(order_id)
      LOGGER.info("[ProcessOrderWorker] (inline) Processing order ##{order_id}")
      Thread.new do
        sleep 0.2
        DB.execute(
          'UPDATE orders SET status = ?, updated_at = ? WHERE id = ?',
          ['processed', Time.now.iso8601, order_id]
        )
        DB.execute(
          'INSERT INTO order_events (order_id, event, created_at) VALUES (?, ?, ?)',
          [order_id, 'processed', Time.now.iso8601]
        )
        LOGGER.info("[ProcessOrderWorker] (inline) Order ##{order_id} marked as processed")
      rescue => e
        LOGGER.error("[ProcessOrderWorker] inline error: #{e.message}")
      end
    end
  end
end

# ─── Structured Logging ───────────────────────────────────────────────────────

LOGGER = Logger.new($stdout)
LOGGER.level = Logger::INFO
LOGGER.formatter = proc do |severity, datetime, _prog, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end

# ─── Redis Cache Helper ───────────────────────────────────────────────────────

CACHE_PREFIX = 'order_cache'

def cache_get(key)
  return nil unless REDIS
  cached = REDIS.get("#{CACHE_PREFIX}:#{key}")
  cached ? JSON.parse(cached, symbolize_names: true) : nil
rescue => e
  LOGGER.warn("Redis cache read error: #{e.message}")
  nil
end

def cache_set(key, value, ttl = 60)
  return unless REDIS
  REDIS.setex("#{CACHE_PREFIX}:#{key}", ttl, value.to_json)
rescue => e
  LOGGER.warn("Redis cache write error: #{e.message}")
end

def cache_delete(key)
  return unless REDIS
  REDIS.del("#{CACHE_PREFIX}:#{key}")
rescue => e
  LOGGER.warn("Redis cache delete error: #{e.message}")
end

# ─── Optional: Faye WebSocket ─────────────────────────────────────────────────

ws_available = false
begin
  require 'faye/websocket'
  ws_available = true
rescue LoadError
  warn '[demo] faye-websocket gem not installed — WebSocket echo disabled'
end

# ─── API Key Authentication ───────────────────────────────────────────────────

API_KEYS = ENV.fetch('API_KEYS', 'demo-key-12345').split(',').map(&:strip)

DebugAgent.register_auth_config(:api_key, {
  strategy: 'X-API-Key header',
  secret_present: true,
  token_expiry: 'per-request',
  protected_routes: %w[/api/orders /api/auth-check],
  key_count: API_KEYS.size
})

# ─── Health Checks ────────────────────────────────────────────────────────────

DebugAgent.register_health_check(:database) do
  begin
    DB.get_first_value('SELECT 1')
    { status: 'UP', detail: 'SQLite query successful' }
  rescue => e
    { status: 'DOWN', error: e.message }
  end
end

DebugAgent.register_health_check(:redis) do
  if REDIS
    begin
      pong = REDIS.ping
      { status: pong == 'PONG' ? 'UP' : 'DEGRADED', detail: "PING -> #{pong}" }
    rescue => e
      { status: 'DOWN', error: e.message }
    end
  else
    { status: 'DEGRADED', detail: 'Redis not configured' }
  end
end

DebugAgent.register_health_check(:memory) do
  rss = `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
  if rss > 500
    { status: 'DEGRADED', detail: "RSS #{rss.round(1)} MB exceeds 500 MB threshold", rss_mb: rss.round(2) }
  else
    { status: 'UP', detail: "RSS #{rss.round(1)} MB within limits", rss_mb: rss.round(2) }
  end
end

# ─── Scheduled Job: Periodic Cleanup ──────────────────────────────────────────

DebugAgent.register_scheduled_job(:cleanup_expired_orders, 'every 30s',
                                   source: 'thread-based', queue: nil)

cleanup_thread = Thread.new do
  loop do
    sleep 30
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      DB.execute('DELETE FROM order_events WHERE created_at < ?', [(Time.now - 3600).iso8601])
      affected = DB.changes
      duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0).round(2)
      DebugAgent.record_job_execution(:cleanup_expired_orders, duration, success: true)
      LOGGER.info("[scheduler] cleanup ran, removed #{affected} old events (#{duration}ms)")
    rescue => e
      duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0).round(2)
      DebugAgent.record_job_execution(:cleanup_expired_orders, duration, success: false, error: e.message)
      LOGGER.error("[scheduler] cleanup failed: #{e.message}")
    end
  end
end
cleanup_thread.name = 'cleanup-scheduler'
cleanup_thread.abort_on_exception = false

# ─── Sinatra Modular App ──────────────────────────────────────────────────────

class OrderApp < Sinatra::Base
  use DebugAgent::RackMiddleware

  set :port, 4567
  set :bind, '0.0.0.0'

  before do
    content_type :json
    @request_start = Time.now
  end

  # API Key auth on protected routes
  before %r{/api/(orders|auth-check)} do
    api_key = request.env['HTTP_X_API_KEY']
    unless api_key && API_KEYS.include?(api_key)
      halt 401, { error: 'Missing or invalid X-API-Key header', hint: "Use header: X-API-Key: #{API_KEYS.first}" }.to_json
    end
  end

  after do
    duration_ms = ((Time.now - @request_start) * 1000).round(2)
    DebugAgent::HttpRequestTracker.record(
      request.request_method, request.path, response.status, duration_ms
    )
    LOGGER.info("#{request.request_method} #{request.path} -> #{response.status} (#{duration_ms}ms)")
  end

  # Capture unhandled exceptions into the error tracking ring buffer
  error StandardError do
    err = env['sinatra.error']
    DebugAgent.record_error(err, path: request.path, method: request.request_method)
    LOGGER.error("Unhandled error: #{err.class}: #{err.message}")
    status 500
    { error: err.message, class: err.class.name }.to_json
  end

  # ─── Health & Utility ──────────────────────────────────────────────────────

  get '/api/health' do
    redis_status = begin
      REDIS ? (REDIS.ping == 'PONG' ? 'UP' : 'DOWN') : 'NOT_CONFIGURED'
    rescue
      'DOWN'
    end

    db_status = begin
      DB.get_first_value('SELECT 1')
      'UP'
    rescue
      'DOWN'
    end

    order_count = DB.get_first_value('SELECT COUNT(*) FROM orders') rescue 0

    {
      status: (redis_status == 'UP' || db_status == 'UP') ? 'UP' : 'DEGRADED',
      uptime_seconds: (Time.now - DebugAgent::PROCESS_START_TIME).round(0),
      orders: order_count,
      services: {
        redis: redis_status,
        database: db_status,
        sidekiq: sidekiq_available ? 'ENABLED' : 'INLINE'
      }
    }.to_json
  end

  get '/api/slow' do
    sleep 0.5
    { message: 'This endpoint intentionally sleeps 500ms', duration_ms: 500 }.to_json
  end

  get '/api/error' do
    LOGGER.error('Intentional error triggered')
    halt 500, { error: 'Intentional 500 error for testing' }.to_json
  end

  # ─── Security & Error Tracking ─────────────────────────────────────────────

  get '/api/panic' do
    raise RuntimeError, 'Intentional panic for error tracking demo!'
  end

  get '/api/auth-check' do
    {
      authenticated: true,
      api_key: request.env['HTTP_X_API_KEY'],
      strategy: 'X-API-Key header',
      protected_routes: %w[/api/orders /api/auth-check]
    }.to_json
  end

  # ─── WebSocket Echo (faye-websocket) ────────────────────────────────────────

  get '/ws' do
    if ws_available && defined?(::Faye::WebSocket) && Faye::WebSocket.websocket?(env)
      ws = Faye::WebSocket.new(env)
      conn_id = ws.object_id
      remote = request.ip

      ws.on :open do |_event|
        DebugAgent.track_ws_connection(conn_id, remote, 'echo')
        LOGGER.info("[ws] connection opened from #{remote} (id=#{conn_id})")
      end

      ws.on :message do |event|
        msg = event.data
        DebugAgent.log_ws_message(conn_id, 'received', msg)
        ws.send(msg)
        DebugAgent.log_ws_message(conn_id, 'sent', msg)
        LOGGER.info("[ws] echoed from #{conn_id}: #{msg.to_s[0...80]}")
      end

      ws.on :close do |_event|
        DebugAgent.untrack_ws_connection(conn_id)
        LOGGER.info("[ws] connection closed (id=#{conn_id})")
      end

      ws.rack_response
    else
      content_type :html
      '<html><body><h1>WebSocket Echo Server</h1>' \
        '<p>Connect using a WebSocket client to ws://localhost:4567/ws</p>' \
        '<p>faye-websocket is not installed. Install with: gem install faye-websocket</p>' \
        '</body></html>'
    end
  end

  # ─── Orders CRUD (SQLite3 + Redis cache) ───────────────────────────────────

  get '/api/orders' do
    rows = DB.execute('SELECT * FROM orders ORDER BY id')
    {
      total: rows.size,
      orders: rows.map { |row| db_order_from_row(row) }
    }.to_json
  end

  get '/api/orders/:id' do
    id = params[:id].to_i

    # Try Redis cache first
    if (cached = cache_get(id))
      LOGGER.info("Cache HIT for order ##{id}")
      cached[:cached] = true
      return cached.to_json
    end

    row = DB.get_first_row('SELECT * FROM orders WHERE id = ?', [id])
    if row
      order = db_order_from_row(row)
      cache_set(id, order)
      LOGGER.info("Cache MISS for order ##{id} — cached for 60s")
      order.to_json
    else
      status 404
      { error: "Order ##{id} not found" }.to_json
    end
  end

  post '/api/orders' do
    body = JSON.parse(request.body.read)

    customer = body['customer'] || 'Unknown'
    item = body['item'] || 'Unknown item'
    quantity = (body['quantity'] || 1).to_i
    price = (body['price'] || 0.0).to_f
    total = quantity * price
    now = Time.now.iso8601

    DB.execute(
      'INSERT INTO orders (customer, item, quantity, price, total, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [customer, item, quantity, price, total, 'pending', now]
    )

    id = DB.last_insert_row_id

    DB.execute(
      'INSERT INTO order_events (order_id, event, created_at) VALUES (?, ?, ?)',
      [id, 'created', now]
    )

    order = {
      id: id, customer: customer, item: item, quantity: quantity,
      price: price, total: total, status: 'pending',
      created_at: now, updated_at: nil
    }

    cache_set(id, order)
    LOGGER.info("Created order ##{id} for #{customer}")

    # Enqueue background processing job
    ProcessOrderWorker.perform_async(id)
    LOGGER.info("Enqueued ProcessOrderWorker for order ##{id}")

    status 201
    order.to_json
  rescue JSON::ParserError
    status 400
    { error: 'Invalid JSON body' }.to_json
  end

  put '/api/orders/:id' do
    id = params[:id].to_i
    body = JSON.parse(request.body.read)

    row = DB.get_first_row('SELECT * FROM orders WHERE id = ?', [id])
    if row.nil?
      status 404
      return { error: "Order ##{id} not found" }.to_json
    end

    customer = body.fetch('customer', row['customer'])
    item = body.fetch('item', row['item'])
    quantity = body.fetch('quantity', row['quantity']).to_i
    price = body.fetch('price', row['price']).to_f
    total = quantity * price
    now = Time.now.iso8601
    status_val = body.fetch('status', row['status'])

    DB.execute(
      'UPDATE orders SET customer = ?, item = ?, quantity = ?, price = ?, total = ?, status = ?, updated_at = ? WHERE id = ?',
      [customer, item, quantity, price, total, status_val, now, id]
    )

    order = {
      id: id, customer: customer, item: item, quantity: quantity,
      price: price, total: total, status: status_val,
      created_at: row['created_at'], updated_at: now
    }

    cache_set(id, order)
    LOGGER.info("Updated order ##{id}")
    order.to_json
  rescue JSON::ParserError
    status 400
    { error: 'Invalid JSON body' }.to_json
  end

  post '/api/orders/:id/complete' do
    id = params[:id].to_i
    row = DB.get_first_row('SELECT * FROM orders WHERE id = ?', [id])

    if row
      now = Time.now.iso8601
      DB.execute(
        'UPDATE orders SET status = ?, updated_at = ? WHERE id = ?',
        ['completed', now, id]
      )
      DB.execute(
        'INSERT INTO order_events (order_id, event, created_at) VALUES (?, ?, ?)',
        [id, 'completed', now]
      )
      cache_delete(id)
      LOGGER.info("Order ##{id} marked as completed")

      order = db_order_from_row(DB.get_first_row('SELECT * FROM orders WHERE id = ?', [id]))
      order.to_json
    else
      status 404
      { error: "Order ##{id} not found" }.to_json
    end
  end

  delete '/api/orders/:id' do
    id = params[:id].to_i
    row = DB.get_first_row('SELECT * FROM orders WHERE id = ?', [id])

    if row
      DB.execute('DELETE FROM orders WHERE id = ?', [id])
      DB.execute(
        'INSERT INTO order_events (order_id, event, created_at) VALUES (?, ?, ?)',
        [id, 'deleted', Time.now.iso8601]
      )
      cache_delete(id)
      LOGGER.info("Deleted order ##{id}")
      { status: 'deleted', id: id }.to_json
    else
      status 404
      { error: "Order ##{id} not found" }.to_json
    end
  end

  # ─── Seed Data ─────────────────────────────────────────────────────────────

  def self.seed_data!
    existing = DB.get_first_value('SELECT COUNT(*) FROM orders')
    return LOGGER.info('Seed data already present, skipping') if existing.to_i > 0

    seeds = [
      { customer: 'Alice Chen', item: 'Ruby Programming Book', quantity: 2, price: 39.99 },
      { customer: 'Bob Smith', item: 'Mechanical Keyboard', quantity: 1, price: 129.00 },
      { customer: 'Carol Johnson', item: 'Wireless Mouse', quantity: 3, price: 24.50 }
    ]

    seeds.each do |seed|
      now = Time.now.iso8601
      total = seed[:quantity] * seed[:price]
      DB.execute(
        'INSERT INTO orders (customer, item, quantity, price, total, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [seed[:customer], seed[:item], seed[:quantity], seed[:price], total, 'pending', now]
      )
      DB.execute(
        'INSERT INTO order_events (order_id, event, created_at) VALUES (?, ?, ?)',
        [DB.last_insert_row_id, 'created', now]
      )
    end

    LOGGER.info("Seeded #{seeds.size} sample orders")
  end
end

# ─── Bootstrap ─────────────────────────────────────────────────────────────────

OrderApp.seed_data!

puts ''
puts '  Ruby Debug Agent Demo'
puts '  Sinatra Order Management API'
puts "  Redis:        #{redis_available ? 'enabled' : 'disabled (no cache)'}"
puts "  Sidekiq:      #{sidekiq_available ? 'enabled' : 'inline (fallback)'}"
puts "  SQLite3:      #{DB_PATH}"
puts "  Open http://localhost:4567/agent"
puts ''
puts '  API Endpoints:'
puts '    GET    /api/orders             - List all orders (requires X-API-Key)'
puts '    POST   /api/orders             - Create new order (enqueues worker)'
puts '    GET    /api/orders/:id         - Get order by ID (Redis cached)'
puts '    PUT    /api/orders/:id         - Update order'
puts '    POST   /api/orders/:id/complete - Complete order'
puts '    DELETE /api/orders/:id         - Delete order'
puts '    GET    /api/health             - Health check (Redis + DB status)'
puts '    GET    /api/slow               - Slow endpoint (500ms)'
puts '    GET    /api/error              - Intentional 500 error'
puts '    GET    /api/panic              - Triggers RuntimeError (error tracking)'
puts '    GET    /api/auth-check         - Auth info (requires X-API-Key)'
puts '    GET    /ws                     - WebSocket echo (if faye-websocket)'
puts ''
puts "  API Key:       #{API_KEYS.first} (header: X-API-Key)"
puts "  WebSocket:     #{ws_available ? 'enabled (faye-websocket)' : 'disabled (gem not installed)'}"
puts ''

OrderApp.run!
