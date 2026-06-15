# frozen_string_literal: true

require "fileutils"

module Crimson
  module Tools
    # Write content to a file, creating parent directories and showing a diff.
    module WriteFile
      TOOL_NAME = "write_file"

      # Tool parameter definitions.
      PARAMS = {
        path: { type: "string", description: "The path to the file to write" },
        content: { type: "string", description: "The content to write" }
      }.freeze

      MUTATION_QUEUE = FileMutationQueue.new

      # @return [Hash] OpenAI-compatible tool definition
      def self.definition
        Schema.build(name: TOOL_NAME, description: "Write content to a file. Creates the file and parent directories if needed.", parameters: PARAMS, required: %w[path content])
      end

      # @return [Hash] Anthropic-compatible tool definition
      def self.anthropic_definition
        Schema.build_anthropic(name: TOOL_NAME, description: "Write content to a file. Creates the file and parent directories if needed.", parameters: PARAMS, required: %w[path content])
      end

      # Execute the tool.
      # @param path [String] file path
      # @param content [String] content to write
      # @return [String] result message with diff or error
      def self.call(path:, content:)
        return "Error: No path provided" if path.nil? || path.strip.empty?

        expanded = File.expand_path(path)

        MUTATION_QUEUE.with_file(expanded) do
          dir = File.dirname(expanded)
          old_content = File.exist?(expanded) ? File.read(expanded) : nil

          FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
          File.write(expanded, content)

          diff = DiffUtil.format_diff(old_content || "", content, path)
          "Successfully wrote to #{path}\n#{diff}"
        end
      rescue => e
        "Error writing file: #{e.message}"
      end
    end
  end
end
