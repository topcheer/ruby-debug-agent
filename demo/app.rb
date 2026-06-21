# Demo: Order Management API with Debug Agent
# Run: ruby demo/app.rb
# Open: http://localhost:4567/agent

require 'json'
require_relative '../lib/debug_agent'

# Simple Rack-based demo server
# In production, you'd use: use DebugAgent::RackMiddleware

class DemoApp
  def call(env)
    path = env['PATH_INFO']
    method = env['REQUEST_METHOD']

    # --- Debug Agent routes (built-in) ---
    agent = DebugAgent::RackMiddleware.new(self)
    result = agent.call(env)
    return result if result[0] != 404

    # --- Demo API ---
    start = Time.now

    response = case [method, path]
    when ['GET', '/api/orders']
      [200, { 'Content-Type' => 'application/json' }, [$orders.to_json]]
    when ['POST', '/api/orders']
      body = JSON.parse(env['rack.input'].read)
      id = $next_id
      $next_id += 1
      order = { id: id, **body, total: body['quantity'] * body['price'] }
      $orders[id] = order
      [201, { 'Content-Type' => 'application/json' }, [order.to_json]]
    when ['GET', '/api/health']
      [200, { 'Content-Type' => 'application/json' }, [{ status: 'UP', orders: $orders.size }.to_json]]
    when ['GET', '/api/slow']
      sleep 0.5
      [200, { 'Content-Type' => 'application/json' }, [{ message: 'This was slow' }.to_json]]
    when ['GET', '/api/error']
      [500, { 'Content-Type' => 'application/json' }, [{ error: 'Intentional error' }.to_json]]
    else
      [404, { 'Content-Type' => 'application/json' }, [{ error: 'Not found' }.to_json]]
    end

    duration_ms = (Time.now - start) * 1000
    DebugAgent::HttpRequestTracker.record(method, path, response[0], duration_ms)

    response
  end
end

# Initialize demo data
$orders = {}
$next_id = 1

# Start server
require 'webrick'

app = DemoApp.new
server = WEBrick::HTTPServer.new(Port: 4567)
server.mount_proc '/' do |req, res|
  status, headers, body = app.call(
    'REQUEST_METHOD' => req.request_method,
    'PATH_INFO' => req.path,
    'QUERY_STRING' => req.query_string || '',
    'rack.input' => StringIO.new(req.body || ''),
    'rack.url_scheme' => 'http'
  )
  res.status = status
  headers.each { |k, v| res[k] = v }
  res.body = body.join
end

trap('INT') { server.shutdown }

puts "\n  Ruby Debug Agent Demo"
puts "  Open http://localhost:4567/agent\n"
server.start
