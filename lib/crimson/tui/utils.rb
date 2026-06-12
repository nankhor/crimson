# frozen_string_literal: true

module Crimson
  module Tui
    module Utils
      # Match ANSI escape sequences (SGR, OSC, APC, CSI, etc.)
      ANSI_SEQUENCE = /\e\[[0-9;]*[A-Za-z]|\e\][^\x07]*\x07|\e[()][A-Z0-9]|\e[>=]|\e\[[?][0-9;]*[A-Za-z]/

      # East Asian wide characters (simplified - covers most common cases)
      WIDE_CHAR_RANGES = [
        (0x1100..0x115F),   # Hangul Jamo
        (0x2E80..0x303E),   # CJK Radicals
        (0x3040..0x33BF),   # Hiragana, Katakana, etc.
        (0x3400..0x4DBF),   # CJK Unified Ideographs Extension A
        (0x4E00..0x9FFF),   # CJK Unified Ideographs
        (0xA000..0xA4CF),   # Yi Syllables
        (0xAC00..0xD7AF),   # Hangul Syllables
        (0xF900..0xFAFF),   # CJK Compatibility Ideographs
        (0xFE10..0xFE6F),   # Vertical Forms
        (0xFF01..0xFF60),   # Fullwidth Forms
        (0xFFE0..0xFFE6),   # Fullwidth Signs
        (0x20000..0x2A6DF), # CJK Unified Ideographs Extension B
        (0x2A700..0x2B73F), # CJK Unified Ideographs Extension C
        (0x2B740..0x2B81F), # CJK Unified Ideographs Extension D
        (0x2F800..0x2FA1F), # CJK Compatibility Ideographs Supplement
      ].freeze

      module_function

      # Calculate the visible width of a string, accounting for ANSI sequences and wide chars
      def visible_width(str)
        return 0 if str.nil? || str.empty?

        width = 0
        i = 0
        while i < str.length
          # Skip ANSI escape sequences
          if str[i] == "\e"
            match = str.match(ANSI_SEQUENCE, i)
            if match && match.begin(0) == i
              i += match[0].length
              next
            end
          end

          # Skip zero-width characters
          char = str[i]
          code = char.ord

          # Zero-width characters
          if code == 0x200B || # Zero Width Space
             code == 0x200C || # Zero Width Non-Joiner
             code == 0x200D || # Zero Width Joiner
             code == 0xFEFF || # Zero Width No-Break Space
             (code >= 0x0300 && code <= 0x036F) || # Combining Diacritical Marks
             (code >= 0x1DC0 && code <= 0x1DFF) || # Combining Diacritical Marks Supplement
             (code >= 0x20D0 && code <= 0x20FF)    # Combining Diacritical Marks for Symbols
            i += 1
            next
          end

          # Wide characters (2 columns)
          if wide_char?(code)
            width += 2
          else
            width += 1
          end

          i += 1
        end

        width
      end

      # Check if a character code is a wide character
      def wide_char?(code)
        WIDE_CHAR_RANGES.any? { |range| range.include?(code) }
      end

      # Truncate a string to a maximum visible width
      def truncate_to_width(str, max_width, suffix = "")
        return "" if str.nil? || str.empty?

        width = 0
        result = String.new
        i = 0

        while i < str.length
          # Pass through ANSI sequences
          if str[i] == "\e"
            match = str.match(ANSI_SEQUENCE, i)
            if match && match.begin(0) == i
              result << match[0]
              i += match[0].length
              next
            end
          end

          char = str[i]
          code = char.ord
          char_width = wide_char?(code) ? 2 : 1

          if width + char_width > max_width
            result << suffix
            break
          end

          result << char
          width += char_width
          i += 1
        end

        result
      end

      # Wrap text with ANSI awareness, preserving styling across line breaks
      def wrap_text(text, width)
        return [""] if text.nil? || text.empty?

        lines = []
        current_line = String.new
        current_width = 0
        ansi_state = "" # Track current ANSI state to reapply after line breaks
        i = 0

        while i < text.length
          # Handle ANSI sequences
          if text[i] == "\e"
            match = text.match(ANSI_SEQUENCE, i)
            if match && match.begin(0) == i
              seq = match[0]
              current_line << seq
              # Track SGR sequences (color/style changes)
              if seq =~ /\e\[[0-9;]*m/
                ansi_state = seq
              end
              i += seq.length
              next
            end
          end

          char = text[i]

          # Handle newlines
          if char == "\n"
            lines << current_line
            current_line = String.new
            current_width = 0
            # Reapply ANSI state after newline
            current_line << ansi_state unless ansi_state.empty?
            i += 1
            next
          end

          code = char.ord
          char_width = wide_char?(code) ? 2 : 1

          # Wrap if we'd exceed width
          if current_width + char_width > width && current_width > 0
            lines << current_line
            current_line = String.new
            current_width = 0
            # Reapply ANSI state after wrap
            current_line << ansi_state unless ansi_state.empty?
          end

          current_line << char
          current_width += char_width
          i += 1
        end

        lines << current_line unless current_line.empty?
        lines.empty? ? [""] : lines
      end

      # Slice a string by column positions (visible width)
      def slice_by_column(str, start_col, end_col, strict: false)
        return "" if str.nil? || str.empty?

        result = String.new
        col = 0
        i = 0
        in_range = false

        while i < str.length
          # Pass through ANSI sequences
          if str[i] == "\e"
            match = str.match(ANSI_SEQUENCE, i)
            if match && match.begin(0) == i
              result << match[0] if in_range
              i += match[0].length
              next
            end
          end

          code = str[i].ord
          char_width = wide_char?(code) ? 2 : 1

          if col >= start_col && (end_col.nil? || col < end_col)
            in_range = true
            result << str[i]
          elsif strict && col >= end_col
            break
          end

          col += char_width
          i += 1
        end

        result
      end

      # Strip all ANSI sequences from a string
      def strip_ansi(str)
        return "" if str.nil?
        str.gsub(ANSI_SEQUENCE, "")
      end

      # Reset ANSI state
      RESET = "\e[0m"

      # Apply a color/style function to text and reset after
      def apply_style(text, style_code)
        "#{style_code}#{text}#{RESET}"
      end
    end
  end
end
