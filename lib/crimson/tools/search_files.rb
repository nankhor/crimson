# frozen_string_literal: true

require "open3"

module Crimson
  module Tools
    # Search files for regex patterns using ripgrep (preferred) or grep fallback.
    module SearchFiles
      TOOL_NAME = "search_files"

      # Tool parameter definitions.
      PARAMS = {
        pattern: { type: "string", description: "The regex pattern to search for" },
        path: { type: "string", description: "The directory to search in. Defaults to current directory." },
        file_pattern: { type: "string", description: "Glob pattern to filter files (e.g. '*.rb'). Defaults to all files." },
        context_lines: { type: "integer", description: "Number of context lines to show around each match (default: 0)" }
      }.freeze

      # Whether ripgrep is available on this system.
      RG_AVAILABLE = system("which rg > /dev/null 2>&1")

      # @api private
      def self.prepare_arguments(args)
        args["context_lines"] = args["context_lines"].to_i if args["context_lines"]
        args
      end

      # @return [Hash] OpenAI-compatible tool definition
      def self.definition
        Schema.build(name: TOOL_NAME, description: "Search for a regex pattern in files. Returns matching file paths, line numbers, and context.", parameters: PARAMS, required: ["pattern"])
      end

      # @return [Hash] Anthropic-compatible tool definition
      def self.anthropic_definition
        Schema.build_anthropic(name: TOOL_NAME, description: "Search for a regex pattern in files. Returns matching file paths, line numbers, and context.", parameters: PARAMS, required: ["pattern"])
      end

      # Execute the tool.
      # @param pattern [String] regex pattern
      # @param path [String] directory to search (default ".")
      # @param file_pattern [String, nil] glob to filter files
      # @param context_lines [Integer] lines of context around matches
      # @return [String] search results or error
      def self.call(pattern:, path: ".", file_pattern: nil, context_lines: 0)
        return "Error: No pattern provided" if pattern.nil? || pattern.strip.empty?

        expanded = File.expand_path(path)
        context = [context_lines, 5].min

        if RG_AVAILABLE
          search_with_rg(pattern, expanded, file_pattern, context)
        else
          search_with_grep(pattern, expanded, file_pattern, context)
        end
      rescue => e
        "Error searching files: #{e.message}"
      end

      class << self
        private

        # @api private
        def search_with_rg(pattern, path, file_pattern, context)
          cmd = ["rg", "--no-heading", "--line-number", "--color=never"]
          cmd << "-C" << context.to_s if context > 0
          cmd += ["--glob", "!{.git,node_modules,vendor,.bundle,tmp,log}"]
          cmd += ["--glob", file_pattern] if file_pattern
          cmd << "--max-count" << "500"
          cmd << pattern << path

          stdout, stderr, status = Open3.capture3(*cmd)

          return "No matches found." if status.exitstatus == 1
          return "Error: #{stderr}" unless status.success? || status.exitstatus == 2

          truncate_output(stdout)
        end

        # @api private
        def search_with_grep(pattern, path, file_pattern, context)
          cmd = ["grep", "-rn", "--color=never", "-E"]
          cmd << "-C" << context.to_s if context > 0
          cmd += ["--exclude-dir=.git", "--exclude-dir=node_modules", "--exclude-dir=vendor"]
          cmd += ["--exclude-dir=.bundle", "--exclude-dir=tmp", "--exclude-dir=log"]
          cmd += ["--include=#{file_pattern}"] if file_pattern
          cmd << "-m" << "500" if context == 0
          cmd << pattern << path

          stdout, _stderr, status = Open3.capture3(*cmd)

          return "No matches found." if status.exitstatus == 1
          truncate_output(stdout)
        end

        # @api private
        def truncate_output(output)
          lines = output.lines
          if lines.length > 200
            "#{lines.first(200).join}\n... (truncated, #{lines.length - 200} more lines)"
          else
            output
          end
        end
      end
    end
  end
end
