# frozen_string_literal: true

require "pastel"

module Crimson
  class OutputHandler
    RENDER_INTERVAL = 0.05

    def initialize
      @pastel = Pastel.new
      @first_token = false
      @render_buffer = String.new
      @render_thread = nil
      @render_mutex = Mutex.new
      @status_bar = nil
    end

    def attach(agent, status_bar = nil)
      @status_bar = status_bar

      agent.on(Agent::Events::AGENT_START) do
        @first_token = false
        @status_bar&.show_thinking
      end

      agent.on(Agent::Events::MESSAGE_UPDATE) do |_event, delta:, **|
        unless @first_token
          @status_bar&.hide_thinking
          @status_bar&.update(status: :streaming)
          @first_token = true
        end
        @render_mutex.synchronize { @render_buffer << delta }
        start_render_thread unless @render_thread&.alive?
      end

      agent.on(Agent::Events::TOOL_EXECUTION_START) do |_event, tool_name:, args:, **|
        @status_bar&.show_tool(tool_name)
        path = extract_path(args)
        if path
          puts @pastel.bold.cyan("  #{tool_name}(#{path})")
        else
          puts @pastel.bold.cyan("  #{tool_name}")
        end
      end

      agent.on(Agent::Events::TOOL_EXECUTION_END) do |_event, result:, is_error:, **|
        @status_bar&.hide_tool
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
        @status_bar&.show_thinking unless @first_token
      end

      agent.on(Agent::Events::AGENT_END) do
        @status_bar&.hide_thinking
        flush_render_buffer
        usage = agent.token_usage
        cost = agent.cost_tracker.total_cost
        model = agent.config.model rescue ""
        provider = agent.config.provider rescue ""
        @status_bar&.update(
          model: model,
          provider: provider,
          tokens: usage,
          cost: cost,
          status: :idle
        )
      end
    end

    private

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
