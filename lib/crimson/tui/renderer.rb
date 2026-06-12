# frozen_string_literal: true

require "pastel"

module Crimson
  class TuiRenderer
    attr_reader :pastel, :width
    attr_accessor :show_status_bar, :show_tool_panels, :status_line

    def initialize
      @pastel = Pastel.new
      @width = terminal_width
      @mutex = Mutex.new
      @current_output = String.new
      @tool_calls = []
      @spinner_index = 0
      @spinner_frames = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏]
      @show_status_bar = true
      @show_tool_panels = true
      @status_line = ""
    end

    def start
      # No-op - we don't need a background thread
    end

    def stop
      # No-op
    end

    def update_output(text)
      @mutex.synchronize { @current_output = text }
    end

    def append_output(text)
      @mutex.synchronize { @current_output += text }
    end

    def clear_output
      @mutex.synchronize { @current_output = String.new }
    end

    def add_tool_call(tool_name, args)
      @mutex.synchronize do
        @tool_calls << { name: tool_name, args: args, active: true, result: nil, error: false, rendered: false }
      end
    end

    def complete_tool_call(tool_name, result, error: false)
      @mutex.synchronize do
        tc = @tool_calls.reverse.find { |t| t[:name] == tool_name && t[:active] }
        if tc
          tc[:active] = false
          tc[:result] = result
          tc[:error] = error
          tc[:rendered] = false # Re-render to show completion
        end
      end
    end

    def clear_tool_calls
      @mutex.synchronize { @tool_calls.clear }
    end

    def render_now
      render_pending_output
    end

    private

    def render_pending_output
      tool_updates = nil
      status = nil

      @mutex.synchronize do
        tool_updates = render_tool_updates
        status = render_status_bar if @show_status_bar
      end

      $stdout.write(tool_updates) if tool_updates
      $stdout.write(status) if status
      $stdout.flush if tool_updates || status
    end

    def render_tool_updates
      return nil unless @show_tool_panels
      return nil if @tool_calls.empty?

      lines = []
      @tool_calls.last(3).each do |tc|
        next if tc[:rendered]

        status_icon = tc[:active] ? spinner_frame : (tc[:error] ? @pastel.red("✗") : @pastel.green("✓"))
        name = tc[:name]
        args = tc[:args].is_a?(Hash) ? tc[:args].inspect[0..50] : tc[:args].to_s[0..50]
        lines << "\n  #{status_icon} #{@pastel.cyan(name)}(#{args})"
        tc[:rendered] = true
      end

      lines.join
    end

    def render_status_bar
      return nil if @status_line.empty?
      "\n#{@pastel.dim(@status_line.to_s)}"
    end

    def spinner_frame
      frame = @spinner_frames[@spinner_index % @spinner_frames.length]
      @spinner_index += 1
      @pastel.cyan(frame)
    end

    def terminal_width
      require 'io/console'
      IO.console&.winsize&.[](1) || 80
    rescue
      80
    end
  end
end
