# frozen_string_literal: true

require "set"
require "pastel"

module Crimson
  # Streaming output handler with spinner, tool call logging, and usage statistics.
  # Subscribes to agent events to provide real-time terminal feedback.
  class OutputHandler
    # Interval in seconds between render flushes.
    RENDER_INTERVAL = 0.05
    # Spinner animation frame characters.
    SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"].freeze

    # Visual styles for known tools (prefix color and label).
    TOOL_STYLES = {
      "read_file"      => { prefix: "→Read",   color: :blue   },
      "write_file"     => { prefix: "→Write",  color: :green  },
      "edit_file"      => { prefix: "→Edit",   color: :yellow },
      "run_command"    => { prefix: "$",        color: :bright_white },
      "search_files"   => { prefix: "✱Search", color: :cyan   },
      "glob"           => { prefix: "✱Glob",   color: :cyan   },
      "list_directory" => { prefix: "→List",   color: :cyan   }
    }.freeze

    # Extractors to pull display-relevant arguments from tool call argument hashes.
    TOOL_ARG_EXTRACTORS = {
      "read_file"      => ->(a) { a["path"] || a[:path] },
      "write_file"     => ->(a) { a["path"] || a[:path] },
      "edit_file"      => ->(a) { a["path"] || a[:path] },
      "run_command"    => ->(a) { a["command"] || a[:command] },
      "search_files"   => ->(a) { a["pattern"] || a[:pattern] },
      "list_directory" => ->(a) { a["path"] || a[:path] },
      "glob"           => ->(a) { a["pattern"] || a[:pattern] }
    }.freeze

    def initialize
      @pastel = Pastel.new
      @spinner_active = false
      @first_token = false
      @render_buffer = String.new
      @render_thread = nil
      @render_mutex = Mutex.new
      @spinner_thread = nil
      @seen_tool_calls = Set.new
      @thinking_start = nil
      @run_start = nil
    end

    # Subscribe to events on the given agent for output rendering.
    # @param agent [Agent]
    # @return [void]
    def attach(agent)
      agent.on(Agent::Events::AGENT_START) do
        @first_token = false
        Formatter.reset
        @thinking_start = Time.now
        @run_start = Time.now
        start_spinner
      end

      agent.on(Agent::Events::MESSAGE_UPDATE) do |_event, delta:, **|
        unless @first_token
          stop_spinner
          @first_token = true
          if @thinking_start
            elapsed = format("%.1fs", Time.now - @thinking_start)
            puts @pastel.dim("+ Thought: #{elapsed}")
            @thinking_start = nil
          end
        end
        @render_mutex.synchronize { @render_buffer << delta }
        start_render_thread unless @render_thread&.alive?
      end

      agent.on(Agent::Events::TOOL_EXECUTION_START) do |_event, tool_name:, args:, tool_call_id:, **|
        next if @seen_tool_calls.include?(tool_call_id)
        @seen_tool_calls << tool_call_id
        stop_spinner
        $stdout.write("\r\e[2K")
        $stdout.flush
        log_tool_call(tool_name, args)
      end

      agent.on(Agent::Events::TOOL_EXECUTION_END) do |_event, result:, is_error:, tool_call_id:, **|
        next if tool_call_id && @seen_tool_calls.include?("#{tool_call_id}_end")
        @seen_tool_calls << "#{tool_call_id}_end" if tool_call_id
        next unless is_error
        truncated = truncate(result.to_s, 120)
        puts @pastel.red("  ✗ #{truncated}")
      end

      agent.on(Agent::Events::TOOL_EXECUTION_UPDATE) do |_event, tool_name:, partial_result:, **|
        next unless tool_name == "run_command"
        flush_render_buffer
        $stdout.write("\r\e[2K #{@pastel.dim(partial_result)}")
        $stdout.flush
      end

      agent.on(Agent::Events::TURN_START) do |_event, active_skills: []|
        conditional = active_skills.reject { |s| s == "coding" }
        unless conditional.empty?
          stop_spinner
          puts @pastel.dim("+ #{conditional.join(", ")}")
        end
        unless @first_token
          @thinking_start = Time.now
          start_spinner
        end
      end

      agent.on(Agent::Events::AGENT_END) do
        stop_spinner
        flush_render_buffer(final: true)
        @seen_tool_calls.clear
        elapsed = @run_start ? format_elapsed(Time.now - @run_start) : ""
        usage = agent.token_usage
        parts = []
        if usage[:total] > 0
          cost = agent.cost_tracker.total_cost
          cost_str = cost > 0 ? " ($#{format("%.4f", cost)})" : ""
          parts << "tokens: #{usage[:prompt]}↑ #{usage[:completion]}↓ = #{usage[:total]}#{cost_str}"
        end
        parts << "time: #{elapsed}" unless elapsed.empty?
        puts @pastel.dim("\n  #{parts.join("  ·  ")}") unless parts.empty?
      end
    end

    private

    # @api private
    def log_tool_call(tool_name, args)
      style = TOOL_STYLES[tool_name]
      if style
        detail = extract_tool_arg(tool_name, args) || ""
        puts @pastel.decorate("#{style[:prefix]} ", style[:color]) + detail
      else
        detail = extract_tool_arg(tool_name, args)
        puts @pastel.dim("→ #{tool_name}") + (detail ? " #{detail}" : "")
      end
    end

    # @api private
    def format_elapsed(seconds)
      if seconds < 60
        format("%.1fs", seconds)
      else
        mins = (seconds / 60).to_i
        secs = format("%.0f", seconds - mins * 60)
        "#{mins}m #{secs}s"
      end
    end

    # @api private
    def start_spinner
      return if @spinner_active
      @spinner_active = true
      @spinner_thread = Thread.new do
        i = 0
        while @spinner_active
          $stdout.write("\r  \e[36m#{SPINNER_FRAMES[i % SPINNER_FRAMES.length]}\e[0m Thinking...")
          $stdout.flush
          i += 1
          sleep 0.08
        end
        $stdout.write("\r\e[2K")
        $stdout.flush
      end
    end

    # @api private
    def stop_spinner
      return unless @spinner_active
      @spinner_active = false
      @spinner_thread&.join(2)
      @spinner_thread = nil
      $stdout.write("\r\e[2K")
      $stdout.flush
    end

    # @api private
    def start_render_thread
      @render_thread = Thread.new do
        loop do
          sleep RENDER_INTERVAL
          break if flush_render_buffer == :empty
        end
      end
    end

    # @api private
    def flush_render_buffer(final: false)
      data = nil
      @render_mutex.synchronize do
        data = @render_buffer.dup
        @render_buffer.clear
      end
      return :empty if data.nil? || data.empty?

      output = String.new
      lines = if final
                data.split("\n", -1)
              else
                last_newline = data.rindex("\n")
                if last_newline.nil?
                  @render_mutex.synchronize { @render_buffer.prepend(data) }
                  return :empty
                end

                complete = data[0..last_newline]
                remainder = data[(last_newline + 1)..]
                @render_mutex.synchronize { @render_buffer.prepend(remainder) } if remainder
                complete.split("\n", -1)
              end

      lines.each do |line|
        next if line.nil?
        next if line.strip.empty?
        if !output.empty? && header?(line)
          output << "\n"
        end
        styled = Formatter.format_line(line)
        output << styled << "\n"
      end

      $stdout.write(output)
      $stdout.flush
      nil
    end

    # @api private
    def extract_tool_arg(tool_name, args)
      return nil unless args.is_a?(Hash)
      extractor = TOOL_ARG_EXTRACTORS[tool_name]
      extractor ? extractor.call(args) : nil
    rescue
      nil
    end

    # @api private
    def header?(line)
      line.match?(Regexp.new('^\#{1,6}\s'))
    end

    # @api private
    def truncate(text, max_len)
      return "" if text.nil?
      cleaned = text.gsub("\n", "\\n")
      cleaned.length > max_len ? "#{cleaned[0...max_len]}..." : cleaned
    end
  end
end
