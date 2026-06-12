# frozen_string_literal: true

require "io/console"

module Crimson
  module Tui
    class Terminal
      attr_reader :columns, :rows

      def initialize
        @columns = 80
        @rows = 24
        @previous_lines = []
        @cursor_row = 0
        @hardware_cursor_row = 0
        @max_lines_rendered = 0
        @previous_width = 0
        @previous_height = 0
        @previous_viewport_top = 0
        update_size
      end

      def update_size
        size = IO.console&.winsize
        if size
          @rows = size[0]
          @columns = size[1]
        end
      end

      def write(data)
        $stdout.write(data)
        $stdout.flush
      end

      def hide_cursor
        write("\e[?25l")
      end

      def show_cursor
        write("\e[?25h")
      end

      def clear_screen
        write("\e[2J\e[H\e[3J")
      end

      def save_cursor
        write("\e[s")
      end

      def restore_cursor
        write("\e[u")
      end

      # Move cursor to specific row (0-indexed)
      def move_to_row(row)
        delta = row - @hardware_cursor_row
        if delta > 0
          write("\e[#{delta}B")
        elsif delta < 0
          write("\e[#{-delta}A")
        end
        @hardware_cursor_row = row
      end

      # Move cursor to beginning of current line
      def carriage_return
        write("\r")
      end

      # Clear from cursor to end of line
      def clear_to_end_of_line
        write("\e[2K")
      end

      # Clear from cursor to end of screen
      def clear_to_end_of_screen
        write("\e[J")
      end
    end
  end
end
