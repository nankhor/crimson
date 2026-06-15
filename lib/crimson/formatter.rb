# frozen_string_literal: true

require "pastel"

module Crimson
  # ANSI-markdown formatter for rendering Markdown-formatted text with terminal colors.
  module Formatter
    @pastel = Pastel.new(enabled: true)
    @in_code_block = false

    class << self
      # Reset the code block tracking state.
      # @return [void]
      def reset
        @in_code_block = false
      end

      # Format a single line of Markdown text with ANSI styling.
      # @param line [String, nil]
      # @return [String] styled output
      def format_line(line)
        return "" if line.nil?

        if @in_code_block
          if line.start_with?("```")
            @in_code_block = false
            @pastel.dim("```")
          else
            line
          end
        elsif line.start_with?("```")
          @in_code_block = true
          lang = line.sub(/^```\s*/, "").strip
          lang.empty? ? @pastel.dim("```") : @pastel.dim("``` #{lang}")
        else
          style_inline(line)
        end
      end

      # @return [Boolean] whether currently inside a code block
      def in_code_block?
        @in_code_block
      end

      private

      # Apply inline Markdown styling (headers, bold, code, links, etc.).
      # @api private
      def style_inline(line)
        result = line.dup

        header_re = Regexp.new('^\#{1,6}\s+(.+)$')
        if (m = result.match(header_re))
          return @pastel.bold.yellow(m[1])
        end

        result = result.gsub(/^(\s{0,3})([-*+])\s/) do
          "#{$1}#{@pastel.cyan($2)} "
        end

        result = result.gsub(/^(\s{0,3})(\d+\.)\s/) do
          "#{$1}#{@pastel.cyan($2)} "
        end

        result = result.gsub(/^>\s?(.*)$/) do
          @pastel.dim("│ ") + @pastel.dim($1)
        end

        if result.strip =~ /^-{3,}$|^_{3,}$|^\*{3,}$/
          result = @pastel.dim("─" * 40)
        end

        result = result.gsub(/\[([^\]]+)\]\(([^)]+)\)/) do
          @pastel.underline($1) + @pastel.dim(" (#{$2})")
        end

        result = result.gsub(/`([^`]+)`/) do
          @pastel.cyan($1)
        end

        result = result.gsub(/\*\*([^*]+)\*\*/) do
          @pastel.bold($1)
        end

        result = result.gsub(/(?<!\*)\*([^*]+)\*(?!\*)/) do
          @pastel.italic($1)
        end

        result
      end
    end
  end
end
