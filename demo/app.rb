# Demo: Order Management API with Ruby Debug Agent
# Run: ruby demo/app.rb
# Open: http://localhost:4567/agent
#
# Requires: gem install sinatra

require_relative '../lib/debug_agent'

require 'sinatra/base'
require 'json'
require 'logger'
require 'time'

# ─── Sinatra Modular App ─────────────────────────────────────────────────

class OrderApp < Sinatra::Base
  use DebugAgent::RackMiddleware

  set :port, 4567
  set :bind, '0.0.0.0'

  # Thread-safe in-memory storage
  ORDERS = {}
  ORDER_LOCK = Mutex.new
  NEXT_ID = { value: 1 }

  # Structured logging
  LOGGER = Logger.new($stdout)
  LOGGER.level = Logger::INFO
  LOGGER.formatter = proc do |severity, datetime, _prog, msg|
    "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
  end

  before do
    content_type :json
    @request_start = Time.now
  end

  after do
    duration_ms = ((Time.now - @request_start) * 1000).round(2)
    DebugAgent::HttpRequestTracker.record(
      request.request_method, request.path, response.status, duration_ms
    )
    LOGGER.info("#{request.request_method} #{request.path} -> #{response.status} (#{duration_ms}ms)")
  end

  # ─── Health & Utility ──────────────────────────────────────────────────

  get '/api/health' do
    ORDER_LOCK.synchronize do
      { status: 'UP', orders: ORDERS.size, uptime_seconds: (Time.now - DebugAgent::PROCESS_START_TIME).round(0) }.to_json
    end
  end

  get '/api/slow' do
    sleep 0.5
    { message: 'This endpoint intentionally sleeps 500ms', duration_ms: 500 }.to_json
  end

  get '/api/error' do
    LOGGER.error('Intentional error triggered')
    halt 500, { error: 'Intentional 500 error for testing' }.to_json
  end

  # ─── Orders CRUD ───────────────────────────────────────────────────────

  get '/api/orders' do
    ORDER_LOCK.synchronize do
      {
        total: ORDERS.size,
        orders: ORDERS.values
      }.to_json
    end
  end

  get '/api/orders/:id' do
    id = params[:id].to_i
    ORDER_LOCK.synchronize do
      order = ORDERS[id]
      if order
        order.to_json
      else
        status 404
        { error: "Order ##{id} not found" }.to_json
      end
    end
  end

  post '/api/orders' do
    body = JSON.parse(request.body.read)

    ORDER_LOCK.synchronize do
      id = NEXT_ID[:value]
      NEXT_ID[:value] += 1

      order = {
        id: id,
        customer: body['customer'] || 'Unknown',
        item: body['item'] || 'Unknown item',
        quantity: body['quantity'] || 1,
        price: body['price'] || 0.0,
        total: (body['quantity'] || 1).to_f * (body['price'] || 0.0).to_f,
        status: 'pending',
        created_at: Time.now.iso8601
      }

      ORDERS[id] = order
      LOGGER.info("Created order ##{id} for #{order[:customer]}")

      status 201
      order.to_json
    end
  end

  post '/api/orders/:id/complete' do
    id = params[:id].to_i

    ORDER_LOCK.synchronize do
      order = ORDERS[id]
      if order
        order[:status] = 'completed'
        order[:completed_at] = Time.now.iso8601
        LOGGER.info("Order ##{id} marked as completed")
        order.to_json
      else
        status 404
        { error: "Order ##{id} not found" }.to_json
      end
    end
  end

  delete '/api/orders/:id' do
    id = params[:id].to_i

    ORDER_LOCK.synchronize do
      if ORDERS.key?(id)
        ORDERS.delete(id)
        LOGGER.info("Deleted order ##{id}")
        { status: 'deleted', id: id }.to_json
      else
        status 404
        { error: "Order ##{id} not found" }.to_json
      end
    end
  end

  # ─── Seed Data ─────────────────────────────────────────────────────────

  def self.seed_data!
    ORDER_LOCK.synchronize do
      seeds = [
        { customer: 'Alice Chen', item: 'Ruby Programming Book', quantity: 2, price: 39.99 },
        { customer: 'Bob Smith', item: 'Mechanical Keyboard', quantity: 1, price: 129.00 },
        { customer: 'Carol Johnson', item: 'Wireless Mouse', quantity: 3, price: 24.50 }
      ]

      seeds.each do |seed|
        id = NEXT_ID[:value]
        NEXT_ID[:value] += 1
        ORDERS[id] = {
          id: id,
          customer: seed[:customer],
          item: seed[:item],
          quantity: seed[:quantity],
          price: seed[:price],
          total: seed[:quantity] * seed[:price],
          status: 'pending',
          created_at: Time.now.iso8601
        }
      end

      LOGGER.info("Seeded #{seeds.size} sample orders")
    end
  end
end

# ─── Bootstrap ─────────────────────────────────────────────────────────────

OrderApp.seed_data!

puts ''
puts '  Ruby Debug Agent Demo'
puts '  Sinatra Order Management API'
puts "  Open http://localhost:4567/agent"
puts ''
puts '  API Endpoints:'
puts '    GET    /api/orders          - List all orders'
puts '    POST   /api/orders          - Create new order'
puts '    GET    /api/orders/:id      - Get order by ID'
puts '    POST   /api/orders/:id/complete - Complete order'
puts '    DELETE /api/orders/:id      - Delete order'
puts '    GET    /api/health          - Health check'
puts '    GET    /api/slow            - Slow endpoint (500ms)'
puts '    GET    /api/error           - Intentional 500 error'
puts ''

OrderApp.run!
