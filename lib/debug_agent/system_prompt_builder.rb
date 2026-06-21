module DebugAgent
  CATEGORY_MAP = {
    'gc'            => 'Memory & GC',
    'object_space'  => 'Memory & GC',
    'memory'        => 'Memory & GC',
    'object_count'  => 'Memory & GC',
    'allocations'   => 'Memory & GC',
    'force_gc'      => 'Memory & GC',
    'trigger_gc'    => 'Memory & GC',
    'process'       => 'Process Info',
    'cpu'           => 'Process Info',
    'uptime'        => 'Process Info',
    'thread'        => 'Threads',
    'system'        => 'System Info',
    'disk'          => 'System Info',
    'environment'   => 'System Info',
    'routes'        => 'Framework & Routes',
    'middleware'    => 'Framework & Routes',
    'runtime'       => 'Runtime Info',
    'recent'        => 'HTTP Requests',
    'slow'          => 'HTTP Requests',
    'error'         => 'HTTP Requests',
    'request'       => 'HTTP Requests',
    'gem'           => 'Dependencies',
    'module'        => 'Module Info',
  }.freeze

  class SystemPromptBuilder
    def initialize(tool_registry = REGISTRY)
      @registry = tool_registry
    end

    def build
      categories = categorize_tools

      sb = +''
      sb << "You are an expert Ruby runtime debugging assistant.\n"
      sb << "You are running INSIDE the developer's Ruby application and have direct access\n"
      sb << "to its runtime state through diagnostic tools.\n\n"
      sb << "## Your Capabilities\n"
      sb << "You can call tools to inspect the live application. Here are ALL available tools,\n"
      sb << "grouped by category:\n\n"

      categories.keys.sort.each do |category|
        sb << "**#{category}\n"
        categories[category].each do |t|
          sb << "- `#{t[:name]}`: #{truncate(t[:desc])}\n"
        end
        sb << "\n"
      end

      sb << "## Workflow\n"
      sb << "1. Understand the developer's problem description\n"
      sb << "2. Proactively call the most relevant tools to gather diagnostic data\n"
      sb << "3. Analyze the collected data to identify root causes\n"
      sb << "4. Provide clear, actionable solutions with data evidence\n\n"
      sb << "## Guidelines\n"
      sb << "- Be proactive: gather data with tools before answering\n"
      sb << "- Always present data in a readable format (tables, bullet points)\n"
      sb << "- Respond in the same language the developer uses\n"
      sb << "- When you find a problem, explain the root cause and give concrete fix suggestions\n"
      sb << "- You can call multiple tools in parallel if they are independent\n"

      sb.freeze
    end

    private

    def categorize_tools
      categories = Hash.new { |h, k| h[k] = [] }
      @registry.all_schemas.each do |schema|
        fn = schema['function']
        name = fn['name']
        desc = fn['description']
        category = extract_category(name)
        categories[category] << { name: name, desc: desc }
      end
      categories
    end

    def extract_category(tool_name)
      name_lower = tool_name.downcase
      CATEGORY_MAP.each do |keyword, category|
        return category if name_lower.include?(keyword)
      end
      'Other Tools'
    end

    def truncate(desc)
      return '' if desc.nil? || desc.empty?
      period = desc.index('.')
      return desc[0..period] if period && period > 0 && period < 150
      return desc[0..116] + '...' if desc.length > 120
      desc
    end
  end
end
