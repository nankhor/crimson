# frozen_string_literal: true

require "pastel"
require_relative "tui"

module Crimson
  class OutputHandler
    def initialize
      @pastel = Pastel.new
      @tui = Tui::Manager.new
      @first_token = false
      @current_tool = nil
    end

    def attach(agent)
      agent.on(Agent::Events::AGENT_START) do
        @first_token = false
        @tui.show_loader("Thinking...")
        update_status_from_agent(agent, status: "thinking")
      end

      agent.on(Agent::Events::MESSAGE_UPDATE) do |_event, delta:, **|
        unless @first_token
          @tui.hide_loader
          @first_token = true
        end
        @tui.append_markdown(delta)
        update_status_from_agent(agent, status: "streaming")
      end

      agent.on(Agent::Events::TOOL_EXECUTION_START) do |_event, tool_name:, args:, **|
        @tui.hide_loader
        @current_tool = @tui.add_tool_call(tool_name, args)
        update_status_from_agent(agent, status: "tool_running")
      end

      agent.on(Agent::Events::TOOL_EXECUTION_END) do |_event, tool_name:, result:, is_error:, **|
        if @current_tool
          @tui.complete_tool_call(@current_tool, result, is_error: is_error)
          @current_tool = nil
        end
      end

      agent.on(Agent::Events::TOOL_EXECUTION_UPDATE) do |_event, tool_name:, partial_result:, **|
        # Could add partial result display here
      end

      agent.on(Agent::Events::TURN_START) do
        @tui.show_loader("Thinking...") unless @first_token
      end

      agent.on(Agent::Events::AGENT_END) do
        @tui.hide_loader
        update_status_from_agent(agent, status: "idle")
        @tui.clear_markdown # Clear for next turn
      end
    end

    def start
      @tui.start
    end

    def stop
      @tui.stop
    end

    def tui
      @tui
    end

    private

    def update_status_from_agent(agent, status:)
      token_usage = agent.token_usage rescue { prompt: 0, completion: 0, total: 0 }
      cost = agent.cost_tracker.total_cost rescue 0.0
      provider = agent.config.provider rescue ""
      model = agent.config.model rescue ""
      session_name = agent.session_name rescue ""
      cwd = Dir.pwd
      thinking_level = agent.config.thinking_level rescue ""

      @tui.update_status(
        model: model,
        provider: provider,
        token_usage: token_usage,
        cost: cost,
        status: status,
        session_name: session_name,
        cwd: cwd,
        thinking_level: thinking_level
      )
    end
  end
end
