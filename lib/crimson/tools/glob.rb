# frozen_string_literal: true

module Crimson
  module Tools
    # Find files matching a glob pattern with configurable search root.
    module Glob
      TOOL_NAME = "glob"

      # Tool parameter definitions.
      PARAMS = {
        pattern: { type: "string", description: "The glob pattern to match files against" },
        path: { type: "string", description: "The directory to search in. Defaults to current directory." }
      }.freeze

      # @return [Hash] OpenAI-compatible tool definition
      def self.definition
        Schema.build(name: TOOL_NAME, description: "Find files matching a glob pattern (e.g. '**/*.rb', 'src/**/*.ts'). Returns sorted file paths.", parameters: PARAMS, required: ["pattern"])
      end

      # @return [Hash] Anthropic-compatible tool definition
      def self.anthropic_definition
        Schema.build_anthropic(name: TOOL_NAME, description: "Find files matching a glob pattern (e.g. '**/*.rb', 'src/**/*.ts'). Returns sorted file paths.", parameters: PARAMS, required: ["pattern"])
      end

      # Execute the tool.
      # @param pattern [String] glob pattern
      # @param path [String] search root (default ".")
      # @return [String] sorted file paths or error
      def self.call(pattern:, path: ".")
        return "Error: No pattern provided" if pattern.nil? || pattern.strip.empty?

        expanded = File.expand_path(path)
        return "Error: Directory not found: #{path}" unless Dir.exist?(expanded)

        files = Dir.glob(File.join(expanded, pattern)).sort

        if files.empty?
          "No files found matching pattern: #{pattern}"
        elsif files.length > 200
          "#{files.first(200).join("\n")}\n... (truncated, #{files.length - 200} more files)"
        else
          files.join("\n")
        end
      rescue => e
        "Error searching files: #{e.message}"
      end
    end
  end
end
