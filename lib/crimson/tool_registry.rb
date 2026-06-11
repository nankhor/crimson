require 'json'

module Crimson
  class ToolRegistry
    def initialize
      @tools = {}
      @openai_defs = nil
      @anthropic_defs = nil
    end

    def register(tool_module)
      name = tool_module.const_get(:TOOL_NAME)
      @tools[name] = tool_module
      @openai_defs = nil
      @anthropic_defs = nil
    end

    def execute(tool_name, arguments)
      tool = @tools[tool_name]
      return "Error: Unknown tool '#{tool_name}'" unless tool

      args = if arguments.is_a?(String)
               JSON.parse(arguments, symbolize_names: true)
             else
               arguments.transform_keys(&:to_sym)
             end
      tool.call(**args)
    rescue JSON::ParserError
      "Error: Invalid JSON arguments for #{tool_name}"
    rescue ArgumentError => e
      "Error: Wrong arguments for #{tool_name}: #{e.message}"
    rescue => e
      "Error executing #{tool_name}: #{e.message}"
    end

    def openai_definitions
      @openai_defs ||= @tools.values.map(&:definition)
    end

    def anthropic_definitions
      @anthropic_defs ||= @tools.values.map(&:anthropic_definition)
    end

    def lookup(tool_name)
      @tools[tool_name]
    end

    def tool_names
      @tools.keys
    end

    def load_skills(skills_dir)
      return "" unless Dir.exist?(skills_dir)

      Dir.glob(File.join(skills_dir, "*.md")).sort.filter_map do |file|
        File.read(file).strip
      end.join("\n\n")
    end
  end
end
