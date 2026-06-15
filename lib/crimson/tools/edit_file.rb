# frozen_string_literal: true

module Crimson
  module Tools
    # Edit files by replacing strings, with single and multi-edit modes.
    # Handles BOM, CRLF/LF line endings, and produces diffs.
    module EditFile
      TOOL_NAME = "edit_file"

      # Tool parameter definitions.
      PARAMS = {
        path: { type: "string", description: "The path to the file to edit" },
        old_string: { type: "string", description: "The exact string to find and replace (single edit mode)" },
        new_string: { type: "string", description: "The string to replace it with (single edit mode)" },
        replace_all: { type: "boolean", description: "Replace all occurrences (default: false)" },
        edits: {
          type: "array",
          description: "Array of edits for multiple replacements in one call. Each edit has old_string, new_string, and optional replace_all.",
          items: {
            type: "object",
            properties: {
              old_string: { type: "string", description: "The exact string to find" },
              new_string: { type: "string", description: "The replacement string" },
              replace_all: { type: "boolean", description: "Replace all occurrences (default: false)" }
            },
            required: %w[old_string new_string]
          }
        }
      }.freeze

      MUTATION_QUEUE = FileMutationQueue.new

      # @api private
      def self.prepare_arguments(args)
        if args["edits"].is_a?(Array)
          args["edits"].each { |e| e["replace_all"] = !!e["replace_all"] if e.key?("replace_all") }
        end
        args["replace_all"] = !!args["replace_all"] if args.key?("replace_all")
        args
      end

      # @return [Hash] OpenAI-compatible tool definition
      def self.definition
        Schema.build(name: TOOL_NAME, description: "Replace strings in a file. Supports single edit or multiple edits in one call.", parameters: PARAMS, required: ["path"])
      end

      # @return [Hash] Anthropic-compatible tool definition
      def self.anthropic_definition
        Schema.build_anthropic(name: TOOL_NAME, description: "Replace strings in a file. Supports single edit or multiple edits in one call.", parameters: PARAMS, required: ["path"])
      end

      # Execute the tool.
      # @param path [String] file path
      # @param old_string [String, nil] text to find
      # @param new_string [String, nil] replacement text
      # @param replace_all [Boolean] replace all occurrences
      # @param edits [Array<Hash>, nil] multiple edits
      # @return [String] result message with diff or error
      def self.call(path:, old_string: nil, new_string: nil, replace_all: false, edits: nil)
        return "Error: No path provided" if path.nil? || path.strip.empty?

        expanded = File.expand_path(path)

        MUTATION_QUEUE.with_file(expanded) do
          return "Error: File not found: #{path}" unless File.exist?(expanded)
          return "Error: Not a file: #{path}" unless File.file?(expanded)

          content = File.binread(expanded)
          has_bom = content.start_with?("\xEF\xBB\xBF")
          content = content.byteslice(3..) if has_bom
          content = content.force_encoding("UTF-8")

          line_ending = detect_line_ending(content)
          content = content.gsub("\r\n", "\n") if line_ending == :crlf

          old_content = content.dup

          if edits.is_a?(Array) && !edits.empty?
            count = 0
            edits.each do |e|
              result = apply_edit(content, e["old_string"], e["new_string"], e["replace_all"])
              return result[:error] if result[:error]
              content = result[:content]
              count += result[:count]
            end
          elsif old_string
            return "Error: No old_string provided" if old_string.nil? || old_string.empty?

            result = apply_edit(content, old_string, new_string, replace_all)
            return result[:error] if result[:error]

            content = result[:content]
            count = result[:count]
          else
            return "Error: Provide either old_string/new_string or edits array"
          end

          content = content.gsub("\n", "\r\n") if line_ending == :crlf
          content = "\xEF\xBB\xBF#{content}" if has_bom

          File.binwrite(expanded, content)

          clean_old = old_content
          clean_new = has_bom ? content.byteslice(3..) : content
          diff = DiffUtil.format_diff(clean_old, clean_new, path)
          "Successfully edited #{path} (#{count} replacement#{'s' if count != 1})\n#{diff}"
        end
      rescue => e
        "Error editing file: #{e.message}"
      end

      class << self
        private

        # @api private
        def apply_edit(content, old_string, new_string, replace_all = false)
          return { error: "Error: old_string not provided" } if old_string.nil? || old_string.empty?
          return { error: "Error: new_string not provided" } if new_string.nil?

          count = content.scan(Regexp.escape(old_string)).length

          if count == 0
            return { error: "Error: old_string not found in file. Make sure it matches exactly." }
          end

          if !replace_all && count > 1
            return { error: "Error: old_string found #{count} times. It must be unique, or use replace_all: true." }
          end

          new_content = replace_all ? content.gsub(old_string, new_string) : content.sub(old_string, new_string)
          { content: new_content, count: count }
        end

        # @api private
        def detect_line_ending(content)
          crlf_pos = content.index("\r\n")
          lf_pos = content.index("\n")
          return :lf if lf_pos.nil?
          return :lf if crlf_pos.nil?
          crlf_pos < lf_pos ? :crlf : :lf
        end
      end
    end
  end
end
