require 'json'

module DebugAgent
  ToolParam = Struct.new(:description, :required, keyword_init: true) do
    def initialize(description:, required: true)
      super
    end
  end

  ToolDefinition = Struct.new(:name, :description, :func, :params, keyword_init: true)

  class ToolRegistry
    def initialize
      @tools = {}
    end

    def register(tool)
      @tools[tool.name] = tool
    end

    def get(name)
      @tools[name]
    end

    def all_schemas
      @tools.values.map(&:to_schema)
    end

    def execute(name, args)
      tool = @tools[name]
      return { error: "Unknown tool: #{name}" } unless tool

      begin
        result = tool.func.call(**args)
        result
      rescue => e
        { error: e.message }
      end
    end

    def names
      @tools.keys
    end
  end

  module ToolDefinitionExt
    def to_schema
      properties = {}
      required = []

      (params || {}).each do |pname, pmeta|
        properties[pname.to_s] = {
          'type' => pmeta[:type] || 'string',
          'description' => pmeta[:description] || ''
        }
        required << pname.to_s if pmeta[:required] != false
      end

      {
        'type' => 'function',
        'function' => {
          'name' => name,
          'description' => description,
          'parameters' => {
            'type' => 'object',
            'properties' => properties,
            'required' => required
          }
        }
      }
    end
  end

  # Patch Struct to include schema method
  ToolDefinition.prepend(ToolDefinitionExt)

  # Global registry singleton
  REGISTRY = ToolRegistry.new

  module ClassMethods
    def registry
      REGISTRY
    end

    def register_tool(name, description, params = {}, &block)
      tool = ToolDefinition.new(
        name: name,
        description: description,
        func: block,
        params: params
      )
      REGISTRY.register(tool)
    end
  end

  extend ClassMethods
end
