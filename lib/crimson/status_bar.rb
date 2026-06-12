# frozen_string_literal: true

require "io/console"
require "pastel"

module Crimson
  class StatusBar
    SPINNER = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

    def initialize(pastel)
      @pastel = pastel
      @model = ""
      @provider = ""
      @tokens = { prompt: 0, completion: 0, total: 0 }
      @cost = 0.0
      @status = :idle
      @tool_name = nil
      @spinner_idx = 0
      @spinner_thread = nil
      @spinner_active = false
      @mutex = Mutex.new
      @stopped = false
      @input_row = 0
      @scroll_bottom = 0
      @bar_height = 3
      @resize_pending = false
    end

    def start
      enter_alternate_screen
      setup_scroll_region
      draw
      setup_signals
    end

    def stop
      return if @stopped
      @stopped = true
      stop_spinner
      leave_alternate_screen
    end

    def update(model: nil, provider: nil, tokens: nil, cost: nil, status: nil, tool_name: nil)
      @mutex.synchronize do
        @model = model if model
        @provider = provider if provider
        @tokens = tokens if tokens
        @cost = cost if cost
        @status = status if status
        @tool_name = tool_name unless tool_name == :__clear
        @tool_name = nil if tool_name == :__clear
      end
      draw
    end

    def show_thinking
      update(status: :thinking)
      start_spinner
    end

    def hide_thinking
      stop_spinner
      update(status: :idle)
    end

    def show_tool(name)
      update(status: :tool, tool_name: name)
    end

    def hide_tool
      update(status: :idle, tool_name: :__clear)
    end

    def write(text)
      $stdout.write(text)
      $stdout.flush
    end

    def write_ln(text)
      write("#{text}\n")
    end

    def flush
      $stdout.flush
    end

    def move_to_input
      $stdout.write(move_to(0, @input_row))
      $stdout.flush
    end

    def handle_resize
      return unless @resize_pending
      @resize_pending = false
      setup_scroll_region
      draw
    end

    private

    def enter_alternate_screen
      $stdout.write("\e[?1049h")
      $stdout.write("\e[?25l")
      $stdout.flush
    end

    def leave_alternate_screen
      $stdout.write("\e[r")
      $stdout.write("\e[?25h")
      $stdout.write("\e[?1049l")
      $stdout.flush
    end

    def setup_scroll_region
      rows, = term_size
      @scroll_bottom = rows - @bar_height
      @input_row = @scroll_bottom - 1
      $stdout.write("\e[1;#{@scroll_bottom}r")
      $stdout.flush
    end

    def draw
      @mutex.synchronize do
        bar_start = @scroll_bottom
        width = term_size[1]

        # Line 1: separator
        $stdout.write(move_to(0, bar_start))
        $stdout.write("\e[2K")
        $stdout.write(@pastel.dim("─" * width))

        # Line 2: model + provider + status
        $stdout.write(move_to(0, bar_start + 1))
        $stdout.write("\e[2K")
        $stdout.write(draw_status_line(width))

        # Line 3: tokens + cost + tool
        $stdout.write(move_to(0, bar_start + 2))
        $stdout.write("\e[2K")
        $stdout.write(draw_info_line(width))

        $stdout.write(move_to(0, @input_row))
        $stdout.flush
      end
    end

    def draw_status_line(width)
      parts = []

      # Status indicator
      case @status
      when :thinking
        frame = SPINNER[@spinner_idx % SPINNER.length]
        parts << @pastel.cyan(" #{frame} thinking")
      when :streaming
        parts << @pastel.cyan(" ⠹ streaming")
      when :tool
        parts << @pastel.yellow(" ⚙ #{@tool_name || 'tool'}")
      else
        parts << @pastel.dim(" ● ready")
      end

      # Model + provider
      unless @model.empty?
        parts << @pastel.bold.cyan(" #{@model}")
      end
      unless @provider.empty?
        parts << @pastel.dim(" (#{@provider})")
      end

      parts.join
    end

    def draw_info_line(width)
      parts = []

      if @tokens[:total] > 0
        parts << @pastel.dim(" #{@tokens[:prompt]}↑ #{@tokens[:completion]}↓ = #{@tokens[:total]}")
      end

      if @cost > 0
        parts << @pastel.dim(" │ $#{format('%.4f', @cost)}")
      end

      parts.empty? ? "" : parts.join
    end

    def start_spinner
      return if @spinner_active
      @spinner_active = true
      @spinner_thread = Thread.new do
        while @spinner_active
          @spinner_idx += 1
          draw
          sleep 0.1
        end
      end
    end

    def stop_spinner
      return unless @spinner_active
      @spinner_active = false
      @spinner_thread&.join(2)
      @spinner_thread = nil
    end

    def setup_signals
      trap("WINCH") { @resize_pending = true }
      at_exit { stop }
    end

    def term_size
      IO.console&.winsize || [24, 80]
    rescue
      [24, 80]
    end

    def move_to(col, row)
      "\e[#{row + 1};#{col + 1}H"
    end
  end
end
