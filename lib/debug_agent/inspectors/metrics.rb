module DebugAgent
  # Inspector for Prometheus metrics (prometheus-client gem).
  # Uses the default registry: Prometheus::Client.registry.

  class << self
    # Resolve the Prometheus registry to inspect.
    def prometheus_registry
      return nil unless defined?(::Prometheus) && defined?(::Prometheus::Client)
      ::Prometheus::Client.respond_to?(:registry) ? ::Prometheus::Client.registry : nil
    end

    # Safely read a metric's value(s). Different metric types return
    # different shapes from #get.
    def prometheus_metric_value(metric)
      begin
        value = metric.get({})
        # Counter/Gauge return a Hash of {labels => value}; unwrap the unlabeled value.
        if value.is_a?(Hash) && value.size == 1 && value.key?({})
          value[{}]
        else
          value
        end
      rescue => e
        { error: e.message }
      end
    end
  end

  register_tool('get_registered_metrics',
                'List registered Prometheus metrics from the prometheus-client gem: ' \
                'name, type, docstring, value') do
    registry = prometheus_registry
    next { error: 'Prometheus client is not loaded (prometheus-client gem not installed)' } unless registry
    next { error: 'No Prometheus registry available' } unless registry.respond_to?(:metrics)

    metrics = registry.metrics.map do |metric|
      {
        name: metric.name,
        type: metric.respond_to?(:type) ? metric.type.to_s : 'unknown',
        docstring: metric.respond_to?(:docstring) ? metric.docstring : nil,
        value: prometheus_metric_value(metric)
      }
    rescue => e
      { name: metric&.respond_to?(:name) ? metric.name : 'unknown', error: e.message }
    end

    { total: metrics.size, metrics: metrics }
  rescue => e
    { error: e.message }
  end

  register_tool('get_metric_value',
                'Get a specific Prometheus metric value by name',
                name: { type: 'string', description: 'Registered metric name' }) do |name:|
    registry = prometheus_registry
    next { error: 'Prometheus client is not loaded (prometheus-client gem not installed)' } unless registry
    next { error: 'No Prometheus registry available' } unless registry.respond_to?(:metrics)

    metric = registry.metrics.find { |m| m.respond_to?(:name) && m.name.to_s == name.to_s }
    next { error: "Metric '#{name}' not found in registry" } unless metric

    {
      name: metric.name,
      type: metric.respond_to?(:type) ? metric.type.to_s : 'unknown',
      docstring: metric.respond_to?(:docstring) ? metric.docstring : nil,
      value: prometheus_metric_value(metric)
    }
  rescue => e
    { error: e.message }
  end
end
