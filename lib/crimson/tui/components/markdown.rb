# frozen_string_literal: true

module Crimson
  module Tui
    module Components
      # Markdown renderer - renders markdown with ANSI styling
      class Markdown < Component
        def initialize(text = "")
          super()
          @text = text
        end

        def set_text(text)
          @text = text
        end

        def append_text(text)
          @text += text
        end

        def render(width)
          return [""] if @text.nil? || @text.empty?

          lines = @text.split("\n")
          result = []
          in_code_block = false

          lines.each do |line|
            if line.start_with?("```")
              in_code_block = !in_code_block
              result << "\e[2m#{line}\e[0m"
              next
            end

            if in_code_block
              result << "\e[2m  #{line}\e[0m"
            else
              result.concat(render_line(line, width))
            end
          end

          result
        end

        private

        def render_line(line, width)
          # Headers
          if line.start_with?("### ")
            return [Utils.truncate_to_width("\e[1;36m#{line[4..]}\e[0m", width)]
          elsif line.start_with?("## ")
            return [Utils.truncate_to_width("\e[1;35m#{line[3..]}\e[0m", width)]
          elsif line.start_with?("# ")
            return [Utils.truncate_to_width("\e[1;34m#{line[2..]}\e[0m", width)]
          end

          # Horizontal rule
          if line =~ /^---+$/ || line =~ /^\*\*\*+$/
            return ["\e[2m#{"─" * width}\e[0m"]
          end

          # Blockquote
          if line.start_with?("> ")
            content = render_inline(line[2..])
            wrapped = Utils.wrap_text(content, width - 2)
            return wrapped.map { |l| "\e[2m│\e[0m #{l}" }
          end

          # Unordered list
          if line =~ /^\s*[-*]\s/
            indent = line[/^\s*/].length
            content = line.sub(/^\s*[-*]\s/, "")
            rendered = render_inline(content)
            prefix = "#{" " * indent}\e[36m•\e[0m "
            wrapped = Utils.wrap_text(rendered, width - indent - 2)
            return wrapped.each_with_index.map { |l, i| i == 0 ? "#{prefix}#{l}" : "#{" " * (indent + 2)}#{l}" }
          end

          # Ordered list
          if line =~ /^\s*\d+\.\s/
            indent = line[/^\s*/].length
            num = line[/(\d+)/, 1]
            content = line.sub(/^\s*\d+\.\s/, "")
            rendered = render_inline(content)
            prefix = "#{" " * indent}\e[36m#{num}.\e[0m "
            wrapped = Utils.wrap_text(rendered, width - indent - 2)
            return wrapped.each_with_index.map { |l, i| i == 0 ? "#{prefix}#{l}" : "#{" " * (indent + 2)}#{l}" }
          end

          # Regular paragraph
          rendered = render_inline(line)
          Utils.wrap_text(rendered, width)
        end

        def render_inline(text)
          # Bold **text**
          text = text.gsub(/\*\*(.+?)\*\*/) { "\e[1m#{$1}\e[0m" }

          # Italic *text*
          text = text.gsub(/\*(.+?)\*/) { "\e[3m#{$1}\e[0m" }

          # Inline code `text`
          text = text.gsub(/`(.+?)`/) { "\e[2m#{$1}\e[0m" }

          # Links [text](url) - just show text dimmed
          text = text.gsub(/\[(.+?)\]\((.+?)\)/) { "\e[4m#{$1}\e[0m \e[2m#{$2}\e[0m" }

          text
        end
      end
    end
  end
end
