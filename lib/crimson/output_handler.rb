# frozen_string_literal: true

require "pastel"
require_relative "tui_manager"

module Crimson
  class OutputHandler
    RENDER_INTERVAL = 0.05

    def initialize
      @pastel = Pastel.new
      @spinner_active = false
      @first_token = false
      @render_buffer = String.new
      @render_thread = nil
      @render_mutex = Mutex.new
      @spinner_thread = nil
      @tui = nil
    end

    def attach(agent)
      @tui = TuiManager.new(agent)
      @tui.start

      agent.on(Agent::Events::AGENT_START) do
        @first_token = false
        start_spinner
        @tui.update_status_bar(status: "thinking")
      end

      agent.on(Agent::Events::MESSAGE_UPDATE) do |_event, delta:, **|
        stop_spinner unless @first_token
        @first_token = true
        @render_mutex.synchronize { @render_buffer << delta }
        start_render_thread unless @render_thread&.alive?
        @tui.update_status_bar(status: "streaming")
      end

      agent.on(Agent::Events::TOOL_EXECUTION_START) do |_event, tool_name:, args:, **|
        stop_spinner
        flush_render_buffer
        @tui.add_tool_call(tool_name, args)
        @tui.render_now
        @tui.update_status_bar(status: "tool_running")
      end

      agent.on(Agent::Events::TOOL_EXECUTION_END) do |_event, tool_name:, result:, is_error:, **|
        @tui.complete_tool_call(tool_name, result, error: is_error)
        @tui.render_now
      end

      agent.on(Agent::Events::TOOL_EXECUTION_UPDATE) do |_event, tool_name:, partial_result:, **|
        # Live updates during tool execution
      end

      agent.on(Agent::Events::TURN_START) do
        start_spinner unless @first_token
      end

      agent.on(Agent::Events::AGENT_END) do
        stop_spinner
        flush_render_buffer
        @tui.update_status_bar(status: "idle")
        @tui.render_now
      end
    end

    def stop
      @tui&.stop
    end

    private

    def start_spinner
      return if @spinner_active
      @spinner_active = true
      @spinner_thread = Thread.new do
        frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        i = 0
        while @spinner_active
          $stdout.write("\r  \e[36m#{frames[i % frames.length]}\e[0m Thinking...")
          $stdout.flush
          i += 1
          sleep 0.08
        end
        $stdout.write("\r\e[2K")
        $stdout.flush
      end
    end

    def stop_spinner
      return unless @spinner_active
      @spinner_active = false
      @spinner_thread&.join(2)
      @spinner_thread = nil
      $stdout.write("\r\e[2K")
      $stdout.flush
    end

    def start_render_thread
      @render_thread = Thread.new do
        loop do
          sleep RENDER_INTERVAL
          break if flush_render_buffer == :empty
        end
      end
    end

    def flush_render_buffer
      data = nil
      @render_mutex.synchronize do
        data = @render_buffer.dup
        @render_buffer.clear
      end
      return :empty if data.nil? || data.empty?
      $stdout.write(data)
      $stdout.flush
      nil
    end
  end
end
