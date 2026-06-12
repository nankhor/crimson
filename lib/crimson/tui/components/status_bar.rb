# frozen_string_literal: true

module Crimson
  module Tui
    module Components
      # Status bar component - shows model, tokens, cost, status
      # Renders at the bottom of the terminal
      class StatusBar < Component
        def initialize
          super()
          @model = ""
          @provider = ""
          @token_usage = { prompt: 0, completion: 0, total: 0 }
          @cost = 0.0
          @status = "idle"
          @session_name = ""
          @cwd = ""
          @thinking_level = ""
        end

        def update(model: nil, provider: nil, token_usage: nil, cost: nil, status: nil,
                   session_name: nil, cwd: nil, thinking_level: nil)
          @model = model if model
          @provider = provider if provider
          @token_usage = token_usage if token_usage
          @cost = cost if cost
          @status = status if status
          @session_name = session_name if session_name
          @cwd = cwd if cwd
          @thinking_level = thinking_level if thinking_level
        end

        def render(width)
          pwd_line = render_pwd_line(width)
          stats_line = render_stats_line(width)
          [pwd_line, stats_line]
        end

        private

        def render_pwd_line(width)
          parts = []
          parts << @cwd unless @cwd.empty?
          parts << "(#{@provider})" unless @provider.empty?
          parts << "\u2022 #{@session_name}" unless @session_name.empty?

          line = parts.join(" ")
          line = Utils.truncate_to_width(line, width, "\e[2m...\e[0m")
          "\e[2m#{line}\e[0m"
        end

        def render_stats_line(width)
          # Left side: tokens and cost
          left_parts = []
          if @token_usage[:total] > 0
            left_parts << format_tokens(@token_usage[:prompt]) if @token_usage[:prompt] > 0
            left_parts << format_tokens(@token_usage[:completion]) if @token_usage[:completion] > 0
          end
          if @cost > 0
            left_parts << "$#{format('%.3f', @cost)}"
          end

          # Status indicator
          status_str = case @status
                       when "thinking" then "\e[33mthinking...\e[0m"
                       when "streaming" then "\e[36mstreaming...\e[0m"
                       when "tool_running" then "\e[35mtool running...\e[0m"
                       else "\e[2midle\e[0m"
                       end
          left_parts.unshift(status_str) unless @status == "idle"

          left = left_parts.join(" ")
          left_width = Utils.visible_width(left)

          # Right side: model + thinking level
          right_parts = []
          right_parts << @model unless @model.empty?
          unless @thinking_level.empty? || @thinking_level == "off"
            right_parts << "\u2022 #{@thinking_level}"
          end
          right = right_parts.join(" ")
          right_width = Utils.visible_width(right)

          # Compose the line
          min_padding = 2
          total_needed = left_width + min_padding + right_width

          if total_needed <= width
            padding = " " * (width - left_width - right_width)
            "#{left}#{padding}\e[2m#{right}\e[0m"
          elsif left_width + min_padding < width
            available = width - left_width - min_padding
            truncated_right = Utils.truncate_to_width(right, available)
            truncated_width = Utils.visible_width(truncated_right)
            padding = " " * [width - left_width - truncated_width, 0].max
            "#{left}#{padding}\e[2m#{truncated_right}\e[0m"
          else
            Utils.truncate_to_width(left, width)
          end
        end

        def format_tokens(count)
          if count < 1000
            count.to_s
          elsif count < 10_000
            "#{(count / 1000.0).round(1)}k"
          elsif count < 1_000_000
            "#{(count / 1000).round}k"
          else
            "#{(count / 1_000_000.0).round(1)}M"
          end
        end
      end
    end
  end
end
