# frozen_string_literal: true

require_relative "tui/renderer"
require_relative "tui/status_bar"
require_relative "tui/tool_panel"
require_relative "tui/markdown"

module Crimson
  class TuiManager
    attr_reader :renderer, :status_bar, :tool_panels, :markdown
    attr_accessor :active, :keyboard_shortcuts_enabled

    def initialize(agent)
      @agent = agent
      @renderer = TuiRenderer.new
      @status_bar = TuiStatusBar.new
      @tool_panels = []
      @markdown = TuiMarkdown.new
      @active = true
      @keyboard_shortcuts_enabled = true
      setup_keyboard_handling
    end

    def start
      return unless @active
      @renderer.start
      update_status_bar
    end

    def stop
      @renderer.stop
    end

    def add_tool_call(name, args = {})
      panel = TuiToolPanel.new(name, args)
      @tool_panels << panel
      @renderer.add_tool_call(name, args)
      update_status_bar(status: "tool_running")
      panel
    end

    def complete_tool_call(name, result = nil, error: false)
      panel = @tool_panels.reverse.find { |t| t.name == name && t.active }
      panel&.complete(result, error: error)
      @renderer.complete_tool_call(name, result, error: error)
      update_status_bar(status: "idle")
      panel
    end

    def clear_tool_panels
      @tool_panels.clear
      @renderer.clear_tool_calls
    end

    def update_status_bar(**kwargs)
      token_usage = @agent.token_usage rescue { prompt: 0, completion: 0, total: 0 }
      cost = @agent.cost_tracker.total_cost rescue 0.0
      provider = @agent.config.provider rescue ""
      model = @agent.config.model rescue ""

      @status_bar.update(
        model: model,
        provider: provider,
        token_usage: token_usage,
        cost: cost,
        **kwargs
      )
      @renderer.status_line = @status_bar.to_s
    end

    def update_output(text)
      @renderer.update_output(text)
    end

    def append_output(text)
      @renderer.append_output(text)
    end

    def append_markdown(text)
      # For now, just pass through as-is to avoid ANSI issues
      @renderer.append_output(text)
    end

    def clear_output
      @renderer.clear_output
    end

    def render_now
      @renderer.render_now
    end

    def toggle_tool_panels
      @renderer.show_tool_panels = !@renderer.show_tool_panels
    end

    def toggle_status_bar
      @renderer.show_status_bar = !@renderer.show_status_bar
    end

    private

    def setup_keyboard_handling
      return unless @keyboard_shortcuts_enabled
      # Keyboard handling will be integrated via the REPL's readline
      # These short cut will be checked in the REPL input loop
    end
  end
end
