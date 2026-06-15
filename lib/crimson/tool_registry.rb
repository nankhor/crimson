# frozen_string_literal: true

require 'json'

module Crimson
  # Central registry for tool registration, execution, and schema generation.
  class ToolRegistry
    def initialize
      @tools = {}
      @openai_defs = nil
      @anthropic_defs = nil
    end

    # Register a tool module by its TOOL_NAME constant.
    # @param tool_module [Module] a tool module with TOOL_NAME, .call, and .definition
    # @return [void]
    def register(tool_module)
      name = tool_module.const_get(:TOOL_NAME)
      @tools[name] = tool_module
      @openai_defs = nil
      @anthropic_defs = nil
    end

    # Execute a tool by name with the given arguments.
    # @param tool_name [String]
    # @param arguments [Hash, String] argument hash or JSON string
    # @param abort_signal [AbortSignal, nil]
    # @return [String] tool result (or error message prefixed with "Error")
    def execute(tool_name, arguments, abort_signal: nil)
      tool = @tools[tool_name]
      return "Error: Unknown tool '#{tool_name}'" unless tool

      args = if arguments.is_a?(String)
               JSON.parse(arguments, symbolize_names: true)
             else
               arguments.transform_keys(&:to_sym)
             end

      if tool.respond_to?(:prepare_arguments)
        begin
          prepared = tool.prepare_arguments(args.transform_keys(&:to_s))
          args = prepared.transform_keys(&:to_sym)
        rescue => e
          return "Error preparing arguments for #{tool_name}: #{e.message}"
        end
      end

      result = if tool.respond_to?(:call_with_signal) && abort_signal
                 tool.call_with_signal(**args, signal: abort_signal)
               else
                 tool.call(**args)
               end

      result = apply_truncation(tool_name, result)

      result
    rescue JSON::ParserError
      "Error: Invalid JSON arguments for #{tool_name}"
    rescue ArgumentError => e
      "Error: Wrong arguments for #{tool_name}: #{e.message}"
    rescue => e
      "Error executing #{tool_name}: #{e.message}"
    end

    # @return [Array<Hash>] OpenAI-compatible tool definitions
    def openai_definitions
      @openai_defs ||= @tools.values.map(&:definition)
    end

    # @return [Array<Hash>] Anthropic-compatible tool definitions
    def anthropic_definitions
      @anthropic_defs ||= @tools.values.map(&:anthropic_definition)
    end

    # Look up a tool module by name.
    # @param tool_name [String]
    # @return [Module, nil]
    def lookup(tool_name)
      @tools[tool_name]
    end

    # @return [Array<String>] all registered tool names
    def tool_names
      @tools.keys
    end

    # Load all skill markdown files from a directory.
    # @param skills_dir [String] directory path
    # @return [String] concatenated skill content
    def load_skills(skills_dir)
      return "" unless Dir.exist?(skills_dir)

      Dir.glob(File.join(skills_dir, "*.md")).sort.filter_map do |file|
        File.read(file).strip
      end.join("\n\n")
    end

    private

    # @api private
    def apply_truncation(tool_name, result)
      return result unless result.is_a?(String)
      return result if result.start_with?("Error")
      return result if result.bytesize <= Tools::Truncator::DEFAULT_MAX_BYTES

      truncation = Tools::Truncator.truncate(result)
      output = truncation.text
      output += "\n\n(full output saved to #{truncation.full_output_path})" if truncation.full_output_path
      output
    end
  end
end
