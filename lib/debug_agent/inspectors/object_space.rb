require 'objspace'

module DebugAgent
  register_tool('get_object_space_stats',
                'Get ObjectSpace.count_objects summary by type (T_STRING, T_ARRAY, etc.)') do
    counts = ObjectSpace.count_objects
    total = counts[:TOTAL] || counts.values.sum

    {
      total_objects: total,
      free_slots: counts[:FREE] || 0,
      by_type: counts.reject { |k, _| k == :TOTAL || k == :FREE }
                     .sort_by { |_, v| -v }
                     .map { |type, count| { type: type.to_s, count: count } }
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_memory_size',
                'Get total memory size of all live objects (ObjectSpace.memsize_of_all)') do
    total_bytes = ObjectSpace.memsize_of_all

    # Also get per-type breakdown
    type_sizes = {}
    ObjectSpace.count_objects.each do |type, count|
      next if type == :TOTAL || type == :FREE || count == 0
      begin
        size = case type
               when :T_STRING then ObjectSpace.memsize_of_all(String)
               when :T_ARRAY then ObjectSpace.memsize_of_all(Array)
               when :T_HASH then ObjectSpace.memsize_of_all(Hash)
               when :T_OBJECT then ObjectSpace.memsize_of_all(Object)
               else 0
               end
        type_sizes[type.to_s] = size if size > 0
      rescue
      end
    end

    {
      total_bytes: total_bytes,
      total_mb: (total_bytes / 1024.0 / 1024.0).round(2),
      total_kb: (total_bytes / 1024.0).round(2),
      top_type_sizes: type_sizes.sort_by { |_, v| -v }.first(10).to_h
    }
  rescue => e
    { error: e.message }
  end

  register_tool('get_object_count_by_class',
                'Get top N classes by instance count using ObjectSpace.each_object') do |top_n: 20|
    counts = Hash.new(0)

    ObjectSpace.each_object do |obj|
      begin
        klass = obj.class
        name = klass.name || klass.to_s
        counts[name] += 1
      rescue
      end
    end

    top = counts.sort_by { |_, v| -v }.first(top_n)

    {
      total_classes: counts.size,
      total_instances: counts.values.sum,
      top_classes: top.map { |name, count| { class: name, count: count } }
    }
  rescue => e
    { error: e.message }
  end
end
