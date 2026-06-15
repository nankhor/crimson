# frozen_string_literal: true

module Crimson
  module Tools
    # List files and directories at a given path, with trailing / for directories.
    module ListDirectory
      TOOL_NAME = "list_directory"

      # Tool parameter definitions.
      PARAMS = {
        path: { type: "string", description: "The directory path to list. Defaults to current directory." }
      }.freeze

      # @return [Hash] OpenAI-compatible tool definition
      def self.definition
        Schema.build(name: TOOL_NAME, description: "List files and directories at the given path.", parameters: PARAMS, required: ["path"])
      end

      # @return [Hash] Anthropic-compatible tool definition
      def self.anthropic_definition
        Schema.build_anthropic(name: TOOL_NAME, description: "List files and directories at the given path.", parameters: PARAMS, required: ["path"])
      end

      # Execute the tool.
      # @param path [String] directory path (defaults to ".")
      # @return [String] sorted listing or error
      def self.call(path: ".")
        expanded = File.expand_path(path)
        return "Error: Directory not found: #{path}" unless Dir.exist?(expanded)

        entries = Dir.entries(expanded).sort - [".", ".."]

        entries.map do |entry|
          full_path = File.join(expanded, entry)
          File.directory?(full_path) ? "#{entry}/" : entry
        end.join("\n")
      rescue => e
        "Error listing directory: #{e.message}"
      end
    end
  end
end
