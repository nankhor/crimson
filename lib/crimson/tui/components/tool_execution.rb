# frozen_string_literal: true

module Crimson
  module Tui
    module Components
      # Tool execution display component
      # Shows tool calls with status, args, and results
      class ToolExecution < Component
        def initialize(name, args = {})
          super()
          @name = name
          @args = args
          @result = nil
          @is_error = false
          @active = true
          @expanded = false
        end

        def complete(result, is_error: false)
          @result = result
          @is_error = is_error
          @active = false
        end

        def set_expanded(expanded)
          @expanded = expanded
        end

        def render(width)
          lines = []

          # Header line with tool name and status
          header = render_header(width)
          lines << header

          # Args (if expanded or active)
          if @expanded || @active
            args_text = format_args
            unless args_text.empty?
              args_lines = Utils.wrap_text(args_text, width - 2)
              args_lines.each { |line| lines << "  #{line}" }
            end
          end

          # Result (if completed and expanded)
          if @result && @expanded
            result_text = @result.to_s
            unless result_text.empty?
              truncated = Utils.truncate_to_width(result_text, width - 2, "...")
              lines << "  \e[2m#{truncated}\e[0m"
            end
          end

          lines
        end

        private

        def render_header(width)
          status_icon = if @active
                         "\e[36m\u2937\e[0m"  # cyan spinner-like
                       elsif @is_error
                         "\e[31m\u2717\e[0m"   # red cross
                       else
                         "\e[32m\u2713\e[0m"   # green check
                       end

          name_str = "\e[1;36m#{@name}\e[0m" # bold cyan

          # Compact args preview
          args_preview = ""
          unless @args.nil? || @args.empty?
            args_str = @args.is_a?(Hash) ? @args.inspect : @args.to_s
            args_preview = "(#{args_str})"
            args_preview = Utils.truncate_to_width(args_preview, 40, "...") if Utils.visible_width(args_preview) > 40
          end

          header = "#{status_icon} #{name_str}#{args_preview}"
          Utils.truncate_to_width(header, width)
        end

        def format_args
          return "" if @args.nil? || @args.empty?
          if @args.is_a?(Hash)
            @args.map { |k, v| "#{k}: #{v}" }.join(", ")
          else
            @args.to_s
          end
        end
      end
    end
  end
end
