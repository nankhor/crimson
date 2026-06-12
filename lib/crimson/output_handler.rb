# frozen_string_literal: true

require "pastel"

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
    end

    def attach(agent)
      agent.on(Agent::Events::AGENT_START) do
        @first_token = false
        start_spinner
      end

      agent.on(Agent::Events::MESSAGE_UPDATE) do |_event, delta:, **|
        stop_spinner unless @first_token
        @first_token = true
        @render_mutex.synchronize { @render_buffer << delta }
        start_render_thread unless @render_thread&.alive?
      end

      agent.on(Agent::Events::TOOL_EXECUTION_START) do |_event, tool_name:, args:, **|
        stop_spinner
        path = extract_path(args)
        if path
          puts @pastel.bold.cyan("  #{tool_name}(#{path})")
        else
          puts @pastel.bold.cyan("  #{tool_name}")
        end
      end

      agent.on(Agent::Events::TOOL_EXECUTION_END) do |_event, result:, is_error:, **|
        truncated = truncate(result.to_s, 200)
        if is_error
          puts @pastel.red("  -> #{truncated}")
        else
          puts @pastel.dim("  -> #{truncated}")
        end
      end

      agent.on(Agent::Events::TOOL_EXECUTION_UPDATE) do |_event, tool_name:, partial_result:, **|
        next unless tool_name == "run_command"
        flush_render_buffer
        $stdout.write("\r #{@pastel.dim(partial_result)}")
        $stdout.flush
      end

      agent.on(Agent::Events::TURN_START) do
        start_spinner unless @first_token
      end

      agent.on(Agent::Events::AGENT_END) do
        stop_spinner
        flush_render_buffer
        usage = agent.token_usage
        if usage[:total] > 0
          cost = agent.cost_tracker.total_cost
          cost_str = cost > 0 ? " ($#{format("%.4f", cost)})" : ""
          puts @pastel.dim("\n  tokens: #{usage[:prompt]}↑ #{usage[:completion]}↓ = #{usage[:total]}#{cost_str}")
        end
      end
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

    def extract_path(args)
      return nil unless args.is_a?(Hash)
      args["path"] || args[:path]
    rescue => e
      nil
    end

    def truncate(text, max_len)
      return "" if text.nil?
      cleaned = text.gsub("\n", "\\n")
      cleaned.length > max_len ? "#{cleaned[0...max_len]}..." : cleaned
    end
  end
end
