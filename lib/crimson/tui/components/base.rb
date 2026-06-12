# frozen_string_literal: true

module Crimson
  module Tui
    module Components
      # Multi-line text with word wrapping
      class Text < Component
        def initialize(text = "", padding_left = 0, padding_right = 0, bg_fn = nil)
          super()
          @text = text
          @padding_left = padding_left
          @padding_right = padding_right
          @bg_fn = bg_fn
        end

        def set_text(text)
          @text = text
        end

        def render(width)
          return [] if @text.nil? || @text.empty?

          available_width = width - @padding_left - @padding_right
          available_width = 1 if available_width < 1

          lines = Utils.wrap_text(@text, available_width)
          lines = lines.map do |line|
            padded = "#{" " * @padding_left}#{line}#{" " * @padding_right}"
            @bg_fn ? @bg_fn.call(padded) : padded
          end

          lines
        end
      end

      # Single-line truncated text
      class TruncatedText < Component
        def initialize(text = "", padding_left = 0, bg_fn = nil)
          super()
          @text = text
          @padding_left = padding_left
          @bg_fn = bg_fn
        end

        def set_text(text)
          @text = text
        end

        def render(width)
          return [""] if @text.nil? || @text.empty?

          available = width - @padding_left
          available = 1 if available < 1

          truncated = Utils.truncate_to_width(@text, available, "...")
          line = "#{" " * @padding_left}#{truncated}"
          [@bg_fn ? @bg_fn.call(line) : line]
        end
      end

      # Animated spinner/loader
      class Loader < Component
        FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"].freeze

        def initialize(text = "Thinking...", color = "\e[36m")
          super()
          @text = text
          @color = color
          @frame_index = 0
        end

        def set_text(text)
          @text = text
        end

        def next_frame
          frame = FRAMES[@frame_index % FRAMES.length]
          @frame_index += 1
          frame
        end

        def render(width)
          frame = next_frame
          line = "#{@color}#{frame}\e[0m #{@text}"
          [Utils.truncate_to_width(line, width)]
        end
      end

      # Box with padding and background
      class Box < Component
        def initialize(padding_top = 0, padding_left = 1, bg_fn = nil)
          super()
          @padding_top = padding_top
          @padding_left = padding_left
          @bg_fn = bg_fn
          @children = []
        end

        def add_child(child)
          @children << child
          self
        end

        def clear
          @children.clear
          self
        end

        def set_bg_fn(fn)
          @bg_fn = fn
        end

        def render(width)
          lines = []

          # Top padding
          @padding_top.times { lines << "" }

          # Render children with left padding
          available = width - @padding_left
          available = 1 if available < 1

          @children.each do |child|
            child_lines = child.render(available)
            child_lines.each do |line|
              padded = "#{" " * @padding_left}#{line}"
              lines << (@bg_fn ? @bg_fn.call(padded) : padded)
            end
          end

          lines
        end
      end

      # Vertical spacer
      class Spacer < Component
        def initialize(lines = 1)
          super()
          @lines = lines
        end

        def render(width)
          Array.new(@lines, "")
        end
      end
    end
  end
end
