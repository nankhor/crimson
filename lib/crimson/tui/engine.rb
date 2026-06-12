# frozen_string_literal: true

module Crimson
  module Tui
    # Main TUI engine with differential rendering
    # Based on Pi's TUI architecture
    class Engine
      RESET = "\e[0m"
      SEGMENT_RESET = "\e[0m"

      def initialize(terminal)
        @terminal = terminal
        @container = Container.new
        @previous_lines = []
        @previous_width = 0
        @previous_height = 0
        @cursor_row = 0
        @hardware_cursor_row = 0
        @max_lines_rendered = 0
        @previous_viewport_top = 0
        @stopped = false
        @render_mutex = Mutex.new
      end

      def container
        @container
      end

      def start
        @stopped = false
        @terminal.hide_cursor
      end

      def stop
        @stopped = true
        @terminal.show_cursor
      end

      def request_render
        do_render
      end

      def render
        do_render
      end

      private

      def do_render
        return if @stopped

        @render_mutex.synchronize do
          @terminal.update_size
          width = @terminal.columns
          height = @terminal.rows

          width_changed = @previous_width != 0 && @previous_width != width
          height_changed = @previous_height != 0 && @previous_height != height

          # Render all components to get new lines
          new_lines = @container.render(width)

          # Apply line resets (ensure each line ends with reset)
          new_lines = apply_line_resets(new_lines)

          # First render - just output everything
          if @previous_lines.empty? && !width_changed && !height_changed
            full_render(new_lines, false)
            return
          end

          # Width changes need full re-render
          if width_changed
            full_render(new_lines, true)
            return
          end

          # Height changes need full re-render
          if height_changed
            full_render(new_lines, true)
            return
          end

          # Content shrunk - clear extra lines
          if new_lines.length < @max_lines_rendered
            full_render(new_lines, true)
            return
          end

          # Find first and last changed lines
          first_changed = -1
          last_changed = -1
          max_lines = [new_lines.length, @previous_lines.length].max

          max_lines.times do |i|
            old_line = i < @previous_lines.length ? @previous_lines[i] : ""
            new_line = i < new_lines.length ? new_lines[i] : ""

            if old_line != new_line
              first_changed = i if first_changed == -1
              last_changed = i
            end
          end

          # Check for appended lines
          appended = new_lines.length > @previous_lines.length
          if appended
            first_changed = @previous_lines.length if first_changed == -1
            last_changed = new_lines.length - 1
          end

          # No changes
          if first_changed == -1
            return
          end

          # All changes are in deleted lines
          if first_changed >= new_lines.length
            if @previous_lines.length > new_lines.length
              clear_extra_lines(new_lines.length)
            end
            @previous_lines = new_lines
            @previous_width = width
            @previous_height = height
            return
          end

          # Differential rendering - only update changed lines
          differential_render(new_lines, first_changed, last_changed, appended)
        end
      end

      def full_render(new_lines, clear)
        buffer = String.new

        if clear
          buffer << "\e[2J\e[H\e[3J" # Clear screen, home, clear scrollback
        end

        new_lines.each_with_index do |line, i|
          buffer << "\r\n" if i > 0
          buffer << line
        end

        @terminal.write(buffer)
        @cursor_row = [0, new_lines.length - 1].max
        @hardware_cursor_row = @cursor_row
        @max_lines_rendered = clear ? new_lines.length : [@max_lines_rendered, new_lines.length].max
        @previous_viewport_top = [0, new_lines.length - @terminal.rows].max
        @previous_lines = new_lines
        @previous_width = @terminal.columns
        @previous_height = @terminal.rows
      end

      def differential_render(new_lines, first_changed, last_changed, appended)
        buffer = String.new

        # Move cursor to first changed line
        target_row = appended ? first_changed - 1 : first_changed
        target_row = [0, target_row].max

        # Handle scrolling if needed
        if target_row > @hardware_cursor_row
          # Need to scroll down
          scroll = target_row - @hardware_cursor_row
          scroll.times { buffer << "\r\n" }
          @hardware_cursor_row = target_row
        else
          # Move cursor to target row
          delta = target_row - @hardware_cursor_row
          if delta > 0
            buffer << "\e[#{delta}B"
          elsif delta < 0
            buffer << "\e[#{-delta}A"
          end
          @hardware_cursor_row = target_row
        end

        buffer << "\r" # Move to column 0

        # Render changed lines
        render_end = [last_changed, new_lines.length - 1].min
        (first_changed..render_end).each do |i|
          buffer << "\r\n" if i > first_changed
          buffer << "\e[2K" # Clear current line
          line = new_lines[i]
          visible = Utils.visible_width(line)
          if visible > @terminal.columns
            line = Utils.truncate_to_width(line, @terminal.columns)
          end
          buffer << line
        end

        @hardware_cursor_row = render_end

        # Clear extra lines if we had more before
        if @previous_lines.length > new_lines.length
          extra = @previous_lines.length - new_lines.length
          extra.times do
            buffer << "\r\n\e[2K"
          end
          buffer << "\e[#{extra}A" # Move cursor back
        end

        @terminal.write(buffer)
        @cursor_row = [0, new_lines.length - 1].max
        @max_lines_rendered = [@max_lines_rendered, new_lines.length].max
        @previous_lines = new_lines
        @previous_width = @terminal.columns
        @previous_height = @terminal.rows
      end

      def clear_extra_lines(from_row)
        buffer = String.new
        delta = from_row - @hardware_cursor_row
        if delta > 0
          buffer << "\e[#{delta}B"
        elsif delta < 0
          buffer << "\e[#{-delta}A"
        end
        @hardware_cursor_row = from_row

        extra = @previous_lines.length - from_row
        extra.times do
          buffer << "\r\n\e[2K"
        end
        buffer << "\e[#{extra}A" if extra > 0

        @terminal.write(buffer)
      end

      def apply_line_resets(lines)
        lines.map do |line|
          # Ensure each line ends with a reset to prevent style leakage
          if line.end_with?(SEGMENT_RESET)
            line
          elsif line.end_with?("\e[0m")
            line
          else
            "#{line}#{SEGMENT_RESET}"
          end
        end
      end
    end
  end
end
