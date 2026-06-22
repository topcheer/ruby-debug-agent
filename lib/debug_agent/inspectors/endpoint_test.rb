require 'net/http'
require 'uri'
require 'json'
require 'time'

module DebugAgent
  @tested_routes = []
  @tested_routes_lock = Mutex.new

  class << self
    attr_reader :tested_routes

    def record_tested_route(method, path, status, duration_ms)
      @tested_routes_lock.synchronize do
        @tested_routes << {
          method: method,
          path: path,
          status: status,
          duration_ms: duration_ms,
          tested_at: Time.now.iso8601
        }
        @tested_routes.shift if @tested_routes.size > 500
      end
    end

    def reset_tested_routes
      @tested_routes_lock.synchronize { @tested_routes.clear }
    end
  end

  class << self
    private

    def app_port
      app = DebugAgent.app
      if app
        app_class = app.is_a?(Class) ? app : app.class
        if app_class.respond_to?(:port)
          return app_class.port
        end
        if app_class.respond_to?(:settings) && app_class.settings.respond_to?(:port)
          return app_class.settings.port
        end
      end
      # Common defaults
      ENV['PORT']&.to_i || 4567
    end

    def app_host
      'localhost'
    end

    def perform_http_request(method, path, headers, body)
      port = app_port
      host = app_host

      uri = URI("http://#{host}:#{port}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = 30
      http.open_timeout = 10

      request_method = Net::HTTP.const_get(method.capitalize)
      req = request_method.new(uri.request_uri)

      # Set headers
      headers&.each do |k, v|
        req[k.to_s] = v.to_s
      end

      # Set body if provided
      if body && !body.to_s.empty?
        req['Content-Type'] ||= 'application/json'
        req.body = body.to_s
      end

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = http.request(req)
      duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2)

      resp_body = response.body
      parsed_body = nil
      begin
        parsed_body = JSON.parse(resp_body) if resp_body && !resp_body.empty?
      rescue JSON::ParserError
        parsed_body = resp_body
      end

      {
        status: response.code.to_i,
        status_message: response.message,
        headers: response.each_header.to_h,
        body: parsed_body,
        duration_ms: duration,
        method: method,
        path: path,
        url: uri.to_s
      }
    rescue Errno::ECONNREFUSED
      { error: "Connection refused — app not running on #{host}:#{app_port}" }
    rescue => e
      { error: "Request failed: #{e.message}", method: method, path: path }
    end
  end

  register_tool('test_endpoint',
                'Send an HTTP request to your own running app. Returns status, headers, body, ' \
                'and duration. Useful for testing API endpoints from the debug agent',
                method: { type: 'string', description: 'HTTP method: GET, POST, PUT, DELETE, PATCH', required: true },
                path: { type: 'string', description: 'Request path (e.g. /api/orders)', required: true },
                headers: { type: 'object', description: 'Optional HTTP headers as key-value pairs (e.g. {"X-API-Key": "demo-key-12345"})', required: false },
                body: { type: 'string', description: 'Optional request body (JSON string for POST/PUT)', required: false }) do |method:, path:, headers: nil, body: nil|
    method_up = method.to_s.upcase
    unless %w[GET POST PUT DELETE PATCH HEAD OPTIONS].include?(method_up)
      next { error: "Unsupported HTTP method: #{method}. Use GET, POST, PUT, DELETE, PATCH, HEAD, or OPTIONS." }
    end

    result = perform_http_request(method_up, path, headers, body)

    if result[:error]
      next result
    end

    record_tested_route(method_up, path, result[:status], result[:duration_ms])

    result
  rescue => e
    { error: e.message }
  end

  register_tool('batch_test_endpoints',
                'Run multiple endpoint tests with assertions. Each test specifies method, path, ' \
                'optional headers/body, and optional assertions (expected_status, expected_body_contains)',
                tests: { type: 'array', description: 'Array of test objects: {method, path, headers?, body?, expected_status?, expected_body_contains?}', required: true }) do |tests:|
    unless tests.is_a?(Array)
      next { error: 'tests must be an array of test objects' }
    end

    results = tests.map do |test|
      test = test.is_a?(Hash) ? test : {}
      method = (test['method'] || test[:method] || 'GET').to_s.upcase
      path = test['path'] || test[:path]
      headers = test['headers'] || test[:headers]
      body = test['body'] || test[:body]

      unless path
        next { method: method, path: '(missing)', error: 'Missing required field: path' }
      end

      http_result = perform_http_request(method, path, headers, body)

      if http_result[:error]
        next { method: method, path: path, error: http_result[:error], passed: false }
      end

      record_tested_route(method, path, http_result[:status], http_result[:duration_ms])

      # Run assertions
      passed = true
      failures = []

      expected_status = test['expected_status'] || test[:expected_status]
      if expected_status && http_result[:status] != expected_status.to_i
        passed = false
        failures << "Expected status #{expected_status}, got #{http_result[:status]}"
      end

      expected_contains = test['expected_body_contains'] || test[:expected_body_contains]
      if expected_contains
        body_str = http_result[:body].is_a?(String) ? http_result[:body] : JSON.generate(http_result[:body])
        unless body_str.include?(expected_contains.to_s)
          passed = false
          failures << "Body does not contain: '#{expected_contains}'"
        end
      end

      {
        method: method,
        path: path,
        status: http_result[:status],
        duration_ms: http_result[:duration_ms],
        passed: passed,
        failures: failures,
        body_preview: (http_result[:body].is_a?(String) ? http_result[:body][0..200] : http_result[:body])
      }
    end

    total = results.size
    passed_count = results.count { |r| r[:passed] }
    failed_count = total - passed_count

    {
      total: total,
      passed: passed_count,
      failed: failed_count,
      pass_rate: total.zero? ? '0%' : format('%.0f%%', passed_count.to_f / total * 100),
      results: results
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_endpoint_coverage',
                'Compare registered Sinatra/Rails routes against tested routes. Shows ' \
                'which endpoints have been tested via the agent and which are untested') do
    # Get all routes from the app
    all_routes = []
    app = DebugAgent.app

    if app
      app_class = app.is_a?(Class) ? app : app.class

      if app_class.respond_to?(:routes)
        app_class.routes.each do |method, route_list|
          route_list.each do |route|
            pattern = route[0]
            pattern_str = case pattern
                          when Regexp then pattern.source
                          else pattern.to_s
                          end
            all_routes << { method: method.to_s.upcase, pattern: pattern_str }
          end
        end
      end
    end

    if all_routes.empty? && defined?(Sinatra) && defined?(Sinatra::Base)
      Sinatra::Base.routes.each do |method, route_list|
        route_list.each do |route|
          pattern = route[0]
          pattern_str = case pattern
                        when Regexp then pattern.source
                        else pattern.to_s
                        end
          all_routes << { method: method.to_s.upcase, pattern: pattern_str }
        end
      end
    end

    tested = tested_routes_lock.synchronize { @tested_routes.dup }
    tested_routes_set = tested.map { |t| "#{t[:method]} #{t[:path]}" }.to_set rescue tested.map { |t| "#{t[:method]} #{t[:path]}" }

    # Match tested routes against app routes
    covered = []
    uncovered = []

    all_routes.each do |route|
      pattern = route[:pattern]
      # Simplify regex patterns for matching (e.g. \A\/api\/orders\/(?<id>[^\/?]+) -> /api/orders)
      base_pattern = pattern
        .gsub(/\A\^?\\A?/, '')
        .gsub(/\$?\\z?\z/, '')
        .gsub(/\(\?<\w+>[^\)]+\)/, ':param')
        .gsub(/\(\?:[^\)]+\)/, ':param')
        .gsub(/\+|\*/, '')
        .gsub(/\\\//, '/')

      was_tested = tested.any? do |t|
        t[:method] == route[:method] && (
          t[:path] == pattern ||
          t[:path].start_with?(base_pattern.gsub(/:param.*/, ''))
        )
      end

      if was_tested
        covered << route
      else
        uncovered << route
      end
    end

    {
      total_routes: all_routes.size,
      tested_routes: tested_routes_set.size,
      covered: covered.size,
      uncovered: uncovered.size,
      coverage_rate: all_routes.empty? ? '0%' : format('%.0f%%', covered.size.to_f / all_routes.size * 100),
      covered_routes: covered,
      uncovered_routes: uncovered,
      recent_tests: tested.last(50)
    }
  rescue => e
    { error: e.message }
  end
end
