# frozen_string_literal: true

module Crimson
  module Tui
    # Main TUI manager - coordinates all components and rendering
    class Manager
      attr_reader :engine, :terminal, :status_bar, :markdown, :loader

      def initialize
        @terminal = Terminal.new
        @engine = Engine.new(@terminal)
        @status_bar = Components::StatusBar.new
        @markdown = Components::Markdown.new
        @loader = Components::Loader.new
        @tool_executions = []
        @chat_container = Container.new
        @show_loader = false
        @render_thread = nil
        @render_requested = false
        @render_mutex = Mutex.new

        setup_layout
      end

      def start
        @engine.start
        start_render_loop
      end

      def stop
        @engine.stop
        stop_render_loop
      end

      def request_render
        @render_requested = true
      end

      # Update status bar
      def update_status(**kwargs)
        @status_bar.update(**kwargs)
        request_render
      end

      # Set markdown content
      def set_markdown(text)
        @markdown.set_text(text)
        request_render
      end

      # Append to markdown
      def append_markdown(text)
        @markdown.append_text(text)
        request_render
      end

      # Clear markdown
      def clear_markdown
        @markdown.set_text("")
        request_render
      end

      # Show/hide loader
      def show_loader(text = "Thinking...")
        @loader.set_text(text)
        @show_loader = true
        request_render
      end

      def hide_loader
        @show_loader = false
        request_render
      end

      # Add tool execution
      def add_tool_call(name, args = {})
        tool = Components::ToolExecution.new(name, args)
        @tool_executions << tool
        @chat_container.add_child(tool)
        request_render
        tool
      end

      # Complete tool execution
      def complete_tool_call(tool, result, is_error: false)
        tool.complete(result, is_error: is_error)
        request_render
      end

      # Clear all tool executions
      def clear_tool_executions
        @tool_executions.each { |t| @chat_container.remove_child(t) }
        @tool_executions.clear
        request_render
      end

      private

      def setup_layout
        # Layout: chat content + loader (optional) + spacer + status bar
        # The engine's container will render these in order
        @engine.container.add_child(@chat_container)
        @engine.container.add_child(@markdown)
      end

      def start_render_loop
        @render_thread = Thread.new do
          loop do
            sleep 0.05 # 20fps
            break if @engine.stopped

            if @render_requested
              @render_requested = false
              rebuild_layout
              @engine.render
            end
          end
        end
      end

      def stop_render_loop
        @render_thread&.join(2)
        @render_thread = nil
      end

      def rebuild_layout
        # Rebuild the layout based on current state
        @engine.container.clear_children

        # Chat content (markdown + tool executions)
        @engine.container.add_child(@chat_container)
        @engine.container.add_child(@markdown)

        # Loader if active
        if @show_loader
          @engine.container.add_child(Components::Spacer.new(1))
          @engine.container.add_child(@loader)
        end

        # Spacer before status bar
        @engine.container.add_child(Components::Spacer.new(1))

        # Status bar at bottom
        @engine.container.add_child(@status_bar)
      end
    end
  end
end
