require "reline"
require "pastel"

module Crimson
class Repl
  RENDER_INTERVAL = 0.05

  def initialize(agent)
    @agent = agent
    @pastel = Pastel.new
    @spinner_active = false
    @first_token_received = false
    @render_buffer = String.new
    @render_thread = nil
    @render_mutex = Mutex.new
    setup_event_handlers
    setup_readline
  end

  def start
    puts @pastel.bold("Crimson v#{VERSION}")
    puts @pastel.dim("Type /help for commands, /exit to quit")
    puts

      loop do
        input = Reline.readline("> ", true)

        break if input.nil?
        input = input.strip
        break if input == "/exit" || input == "/quit"
        next if input.empty?

        if input.start_with?("/")
          handle_command(input)
        else
          begin
            @agent.prompt(input)
          rescue => e
            stop_spinner
            puts @pastel.red("Error: #{e.message}")
          end
        end
      end

      puts @pastel.dim("Goodbye!")
    end

    private

    def setup_event_handlers
      @agent.on(Agent::Events::AGENT_START) do
        @first_token_received = false
        start_spinner
      end

    @agent.on(Agent::Events::MESSAGE_UPDATE) do |_event, delta:, **|
      stop_spinner unless @first_token_received
      @first_token_received = true
      @render_mutex.synchronize { @render_buffer << delta }
      start_render_thread unless @render_thread&.alive?
    end

      @agent.on(Agent::Events::TOOL_EXECUTION_START) do |_event, tool_name:, args:, **|
        stop_spinner
        path = extract_path(args)
        if path
          puts @pastel.bold.cyan("  #{tool_name}(#{path})")
        else
          puts @pastel.bold.cyan("  #{tool_name}")
        end
      end

      @agent.on(Agent::Events::TOOL_EXECUTION_END) do |_event, result:, is_error:, **|
        truncated = truncate(result.to_s, 200)
        if is_error
          puts @pastel.red("  -> #{truncated}")
        else
          puts @pastel.dim("  -> #{truncated}")
        end
      end

    @agent.on(Agent::Events::TOOL_EXECUTION_UPDATE) do |_event, tool_name:, partial_result:, **|
      next unless tool_name == "run_command"
      flush_render_buffer
      $stdout.write("\r #{@pastel.dim(partial_result)}")
      $stdout.flush
    end

      @agent.on(Agent::Events::TURN_START) do
        unless @first_token_received
          start_spinner
        end
      end

    @agent.on(Agent::Events::AGENT_END) do
      stop_spinner
      flush_render_buffer
      usage = @agent.token_usage
        if usage[:total] > 0
          cost = @agent.cost_tracker.total_cost
          cost_str = cost > 0 ? " ($#{format("%.4f", cost)})" : ""
          puts @pastel.dim("\n  tokens: #{usage[:prompt]}↑ #{usage[:completion]}↓ = #{usage[:total]}#{cost_str}")
        end
      end
    end

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

  def handle_command(input)
      case input
      when "/help"
        puts @pastel.bold("Commands:")
        puts "  /help     Show help message"
        puts "  /clear    Clear conversation history"
        puts "  /model    Show current model"
        puts "  /tools    List available tools"
        puts "  /save     Save conversation to file"
        puts "  /load     Load conversation from file"
        puts "  /usage    Show token usage"
        puts "  /sessions List sessions for current directory"
        puts "  /fork     Fork current session into new branch"
        puts "  /tree     Show conversation tree"
        puts "  /compact  Compact conversation history"
        puts "  /exit     Exit crimson"
      when "/clear"
        @agent.reset
        puts @pastel.dim("Conversation cleared.")
      when "/model"
        config = Crimson.config
        puts "Provider: #{PROVIDERS[config.provider.to_sym][:name]}"
        puts "Model: #{config.model}"
      when "/tools"
        puts @pastel.bold("Available tools:")
        @agent.tool_registry.tool_names.each do |name|
          puts "  - #{name}"
        end
      when "/save"
        puts @agent.save_history
      when "/load"
        puts @agent.load_history
      when "/usage"
        usage = @agent.token_usage
        puts @pastel.bold("Token usage:")
        puts "  Prompt:     #{usage[:prompt]}"
        puts "  Completion: #{usage[:completion]}"
        puts "  Total:      #{usage[:total]}"
      when "/sessions"
        unless @agent.session_id
          puts @pastel.dim("No active session.")
          return
        end
        manager = Crimson::SessionManager.new
        sessions = manager.list(cwd: Dir.pwd)
        if sessions.empty?
          puts @pastel.dim("No sessions found.")
        else
          puts @pastel.bold("Sessions:")
          sessions.each do |s|
            current = s.id == @agent.session_id ? " (current)" : ""
            preview = s.preview || "(no preview)"
            puts "  #{@pastel.cyan(s.id[0..7])} #{preview} #{s.last_timestamp}#{current}"
          end
        end
      when "/fork"
        unless @agent.session_id
          puts @pastel.yellow("No active session to fork.")
          return
        end
        manager = Crimson::SessionManager.new
        last_id = @agent.instance_variable_get(:@last_entry_id)
        new_id = manager.fork(@agent.session_id, cwd: Dir.pwd, from_entry_id: last_id)
        @agent.resume_session(new_id, cwd: Dir.pwd, session_manager: manager)
        puts @pastel.dim("Forked to new session: #{new_id[0..7]}")
      when "/tree"
        unless @agent.session_id
          puts @pastel.dim("No active session.")
          return
        end
        manager = Crimson::SessionManager.new
        entries = manager.load(@agent.session_id, cwd: Dir.pwd)
        entries.each do |e|
          case e.role
          when "user"
            content_preview = e.content.to_s.length > 60 ? "#{e.content.to_s[0..57]}..." : e.content.to_s
            puts "  #{@pastel.cyan("⏺")} #{content_preview}"
          when "assistant"
            tool_str = e.tool_calls.any? ? " [#{e.tool_calls.map { |t| t["name"] }.join(", ")}]" : ""
            content_preview = e.content.to_s.length > 60 ? "#{e.content.to_s[0..57]}..." : e.content.to_s
            puts "  #{@pastel.dim("↳ #{content_preview}#{tool_str}")}"
          when "tool_result"
            content_preview = e.content.to_s.length > 40 ? "#{e.content.to_s[0..37]}..." : e.content.to_s
            puts "  #{@pastel.dim("  → #{e.tool_name}: #{content_preview}")}"
          end
        end
      when "/compact"
        if @agent.compactor
          result = @agent.compact!
          puts @pastel.dim(result)
        else
          puts @pastel.yellow("Compaction not enabled.")
        end
      else
        puts @pastel.yellow("Unknown command: #{input}. Type /help for commands.")
      end
    end

    def extract_path(args)
      return nil unless args.is_a?(Hash)
      args["path"] || args[:path]
    rescue
      nil
    end

    def truncate(text, max_len)
      return "" if text.nil?
      cleaned = text.gsub("\n", "\\n")
      cleaned.length > max_len ? "#{cleaned[0...max_len]}..." : cleaned
    end

    def setup_readline
      Reline.completion_proc = method(:file_path_completion)
    end

    def file_path_completion(input)
      prefix = input.strip
      return [] unless prefix.start_with?("@", "./", "~/", "/")

      path_prefix = prefix.start_with?("@") ? prefix[1..] : prefix
      expanded = File.expand_path(path_prefix)

      if File.directory?(expanded)
        Dir.entries(expanded)
          .reject { |e| e.start_with?(".") }
          .map { |e| prefix.end_with?("/") ? "#{prefix}#{e}" : "#{prefix}/#{e}" }
      else
        dir = File.dirname(expanded)
        base = File.basename(expanded)
        return [] unless Dir.exist?(dir)

        Dir.entries(dir)
          .reject { |e| e.start_with?(".") }
          .select { |e| e.downcase.start_with?(base.downcase) }
          .map { |e| prefix.include?("/") ? "#{File.dirname(prefix)}/#{e}" : e }
      end
    rescue => e
      []
    end
  end
end
