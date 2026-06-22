module DebugAgent
  # Registry of named cache objects. Applications register caches so the
  # inspector can introspect stats, keys, and clear them.
  #
  #   DebugAgent.register_cache(:rails, Rails.cache)
  @caches = {}

  class << self
    attr_reader :caches

    def register_cache(name, cache)
      @caches[name.to_s] = cache
    end

    # Introspect a cache object, supporting ActiveSupport::Cache::MemoryStore,
    # generic ActiveSupport::Cache::Store, plain Hashes, and custom caches.
    def cache_stats_for(cache)
      if defined?(::ActiveSupport::Cache::MemoryStore) && cache.is_a?(::ActiveSupport::Cache::MemoryStore)
        data = cache.instance_variable_get(:@data) || {}
        key_access = cache.instance_variable_get(:@key_access) || {}
        {
          type: 'ActiveSupport::Cache::MemoryStore',
          size: data.size,
          max_size: cache.instance_variable_get(:@max_size),
          tracked_keys: key_access.size,
          sample_keys: data.keys.first(50)
        }
      elsif defined?(::ActiveSupport::Cache::Store) && defined?(::ActiveSupport::Cache) &&
            cache.is_a?(::ActiveSupport::Cache::Store)
        stats = best_effort_cache_stats(cache)
        stats.merge(type: cache.class.name)
      elsif cache.is_a?(Hash)
        {
          type: 'Hash',
          size: cache.size,
          sample_keys: cache.keys.first(50)
        }
      else
        stats = best_effort_cache_stats(cache)
        stats.merge(type: cache.class.name)
      end
    end

    # Extract hit/miss and size where the cache exposes them (e.g. Dalli).
    def best_effort_cache_stats(cache)
      result = {}
      result[:size] = cache_size_for(cache)

      if cache.respond_to?(:stats)
        raw =
          begin
            cache.stats
          rescue
            {}
          end
        if raw.is_a?(Hash)
          result[:raw_stats] = raw
          hits = raw['get_hits'] || raw[:get_hits]
          misses = raw['get_misses'] || raw[:get_misses]
          if hits && misses
            total = hits.to_i + misses.to_i
            result[:hits] = hits.to_i
            result[:misses] = misses.to_i
            result[:hit_rate] = total.zero? ? nil : format('%.1f%%', hits.to_f / total * 100)
          end
        end
      end
      result
    end

    def cache_keys_for(cache)
      if defined?(::ActiveSupport::Cache::MemoryStore) && cache.is_a?(::ActiveSupport::Cache::MemoryStore)
        (cache.instance_variable_get(:@data) || {}).keys
      elsif cache.is_a?(Hash)
        cache.keys
      elsif cache.respond_to?(:keys)
        begin
          cache.keys
        rescue
          []
        end
      else
        []
      end
    end

    def cache_size_for(cache)
      if defined?(::ActiveSupport::Cache::MemoryStore) && cache.is_a?(::ActiveSupport::Cache::MemoryStore)
        (cache.instance_variable_get(:@data) || {}).size
      elsif cache.respond_to?(:size)
        begin
          cache.size
        rescue
          nil
        end
      elsif cache.respond_to?(:length)
        begin
          cache.length
        rescue
          nil
        end
      end
    end
  end

  register_tool('get_cache_stats',
                'Get stats for registered caches: hit/miss ratio, size, entries. ' \
                'Supports Rails.cache, ActiveSupport::Cache::MemoryStore, and Hash caches') do |name: nil|
    if caches.empty?
      next { error: 'No caches registered. Call DebugAgent.register_cache(:name, cache).' }
    end

    targets = name ? { name.to_s => caches[name.to_s] } : caches
    targets = targets.reject { |_, c| c.nil? }
    next { error: "No cache registered under '#{name}'" } if targets.empty?

    results = targets.map do |cache_name, cache|
      begin
        cache_stats_for(cache).merge(name: cache_name)
      rescue => e
        { name: cache_name, error: e.message }
      end
    end

    { caches: results }
  rescue => e
    { error: e.message }
  end

  register_tool('get_cache_keys',
                'List keys in a registered cache with optional prefix filter',
                name: { type: 'string', description: 'Registered cache name (optional, defaults to first)', required: false },
                prefix: { type: 'string', description: 'Only return keys starting with this prefix', required: false }) do |name: nil, prefix: nil|
    if caches.empty?
      next { error: 'No caches registered. Call DebugAgent.register_cache(:name, cache).' }
    end

    cache_name, cache = name ? [name.to_s, caches[name.to_s]] : caches.first
    next { error: "No cache registered under '#{name}'" } unless cache

    keys = cache_keys_for(cache)
    if prefix && !prefix.to_s.empty?
      keys = keys.select { |k| k.to_s.start_with?(prefix.to_s) }
    end

    {
      cache: cache_name,
      total_keys: keys.size,
      keys: keys.first(500)
    }
  rescue => e
    { error: e.message }
  end

  register_tool('clear_cache',
                'Clear a registered cache (destructive: removes all entries)',
                name: { type: 'string', description: 'Registered cache name (optional, defaults to first)', required: false }) do |name: nil|
    if caches.empty?
      next { error: 'No caches registered. Call DebugAgent.register_cache(:name, cache).' }
    end

    cache_name, cache = name ? [name.to_s, caches[name.to_s]] : caches.first
    next { error: "No cache registered under '#{name}'" } unless cache

    before = cache_size_for(cache)

    cleared =
      if cache.respond_to?(:clear)
        cache.clear
        true
      elsif cache.is_a?(Hash)
        cache.clear
        true
      elsif cache.respond_to?(:clear_all)
        cache.clear_all
        true
      elsif cache.respond_to?(:delete_all)
        cache.delete_all
        true
      elsif cache.respond_to?(:flushdb)
        cache.flushdb
        true
      else
        false
      end

    next { error: "Cache '#{cache_name}' (#{cache.class}) does not support clearing" } unless cleared

    after = cache_size_for(cache)
    { cache: cache_name, cleared: true, size_before: before, size_after: after }
  rescue => e
    { error: e.message }
  end
end
