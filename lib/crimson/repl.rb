# frozen_string_literal: true

require "reline"
require "pastel"

module Crimson
  class Repl
    def initialize(agent)
      @agent = agent
      @pastel = Pastel.new
      @output_handler = OutputHandler.new
      @output_handler.attach(agent)
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
          @agent.prompt(input)
        end
      rescue => e
        puts @pastel.red("Error: #{e.message}")
      end

      puts @pastel.dim("Goodbye!")
    end

    private

    def handle_command(input)
      case input
      when "/help"
        puts @pastel.bold("Commands:")
        puts "  /help       Show help message"
        puts "  /clear      Clear conversation history"
        puts "  /model      Switch model (interactive selector)"
        puts "  /thinking   Set thinking level (off/low/medium/high)"
        puts "  /tools      List available tools"
        puts "  /save       Save conversation to file"
        puts "  /load       Load conversation from file"
        puts "  /usage      Show token usage and cost"
        puts "  /sessions   List sessions for current directory"
        puts "  /name       Set session name"
        puts "  /session    Show session info"
        puts "  /fork       Fork current session into new branch"
        puts "  /tree       Show conversation tree"
        puts "  /compact    Compact conversation history"
        puts "  /exit       Exit crimson"
      when "/clear"
        @agent.reset
        puts @pastel.dim("Conversation cleared.")
      when "/model"
        handle_model_switch
      when "/thinking"
        handle_thinking
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
        cost = @agent.cost_tracker.total_cost
        puts @pastel.bold("Token usage:")
        puts "  Prompt:     #{usage[:prompt]}"
        puts "  Completion: #{usage[:completion]}"
        puts "  Total:      #{usage[:total]}"
        puts "  Cost:       $#{format('%.4f', cost)}" if cost > 0
      when "/sessions"
        handle_sessions
      when "/name"
        handle_name
      when "/session"
        handle_session_info
      when "/fork"
        handle_fork
      when "/tree"
        handle_tree
      when "/compact"
        if @agent.compactor
          result = @agent.compact!
          puts @pastel.dim(result)
        else
          puts @pastel.yellow("Compaction not enabled.")
        end
      else
        if input.start_with?("/name ")
          handle_name_set(input[6..].strip)
        else
          puts @pastel.yellow("Unknown command: #{input}. Type /help for commands.")
        end
      end
    end

    def handle_sessions
      return puts(@pastel.dim("No active session.")) unless @agent.session_id

      manager = SessionManager.new
      sessions = manager.list(cwd: Dir.pwd)
      if sessions.empty?
        puts @pastel.dim("No sessions found.")
      else
        puts @pastel.bold("Sessions:")
        sessions.each do |s|
          current = s.id == @agent.session_id ? " (current)" : ""
          name_str = s.name ? "[#{s.name}] " : ""
          preview = s.preview || "(no preview)"
          puts "  #{@pastel.cyan(s.id[0..7])} #{name_str}#{preview} #{s.last_timestamp}#{current}"
        end
      end
    end

    def handle_model_switch
      config = @agent.config || Crimson.config
      puts @pastel.dim("Current: #{PROVIDERS[config.provider.to_sym][:name]} / #{config.model}")
      puts

      begin
        prompt = TTY::Prompt.new
        models = fetch_available_models(config)
        if models.empty?
          puts @pastel.yellow("Could not fetch model list. Showing current model only.")
          return
        end

        selected = prompt.select("Select model:", models.map { |m| { name: m, value: m } })
        @agent.switch_model(selected)
        @agent.config.save
        puts @pastel.dim("Switched to: #{selected}")
      rescue => e
        puts @pastel.red("Error switching model: #{e.message}")
      end
    end

    def fetch_available_models(config)
      require "net/http"
      require "uri"
      provider = PROVIDERS[config.provider.to_sym]
      base_url = config.base_url || provider[:base_url]
      url = URI("#{base_url}/models")

      headers = provider[:auth_headers].call(config.api_key)
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = url.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Get.new(url.request_uri, headers)
      response = http.request(request)

      return [] unless response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      (data["data"] || []).map { |m| m["id"] }.sort
    rescue
      []
    end

    def handle_thinking
      config = @agent.config || Crimson.config
      current = config.thinking_level || "off"
      puts @pastel.dim("Current thinking level: #{current}")
      puts

      begin
        prompt = TTY::Prompt.new
        level = prompt.select("Thinking level:", %w[off low medium high].map { |l| { name: l, value: l } })
        config.thinking_level = level
        config.save
        @agent.config = config
        puts @pastel.dim("Thinking level set to: #{level}")
      rescue => e
        puts @pastel.red("Error setting thinking level: #{e.message}")
      end
    end

    def handle_name
      return puts(@pastel.yellow("No active session.")) unless @agent.session_id
      puts @pastel.dim("Usage: /name <session name>")
    end

    def handle_name_set(name)
      return puts(@pastel.yellow("No active session.")) unless @agent.session_id
      return puts(@pastel.yellow("Usage: /name <session name>")) if name.empty?

      manager = SessionManager.new
      manager.set_name(@agent.session_id, cwd: Dir.pwd, name: name)
      puts @pastel.dim("Session name set to: #{name}")
    end

    def handle_session_info
      return puts(@pastel.dim("No active session.")) unless @agent.session_id

      manager = SessionManager.new
      header = manager.load_header(@agent.session_id, cwd: Dir.pwd)
      entries = manager.load(@agent.session_id, cwd: Dir.pwd)

      puts @pastel.bold("Session info:")
      puts "  ID:       #{@agent.session_id}"
      puts "  Name:     #{header&.dig('name') || '(unnamed)'}" if header
      puts "  Created:  #{header&.dig('timestamp')}" if header
      puts "  CWD:      #{@agent.session_cwd}"
      puts "  Entries:  #{entries.length}"

      usage = @agent.token_usage
      puts "  Tokens:   #{usage[:total]} (#{usage[:prompt]} prompt + #{usage[:completion]} completion)"
      cost = @agent.cost_tracker.total_cost
      puts "  Cost:     $#{format('%.4f', cost)}" if cost > 0
    end

    def handle_fork
      return puts(@pastel.yellow("No active session to fork.")) unless @agent.session_id

      manager = SessionManager.new
      last_id = @agent.instance_variable_get(:@last_entry_id)
      new_id = manager.fork(@agent.session_id, cwd: Dir.pwd, from_entry_id: last_id)
      @agent.resume_session(new_id, cwd: Dir.pwd, session_manager: manager)
      puts @pastel.dim("Forked to new session: #{new_id[0..7]}")
    end

    def handle_tree
      return puts(@pastel.dim("No active session.")) unless @agent.session_id

      manager = SessionManager.new
      entries = manager.load(@agent.session_id, cwd: Dir.pwd)
      entries.each do |e|
        case e.role
        when "user"
          preview = truncate(e.content.to_s, 60)
          puts "  #{@pastel.cyan("⏺")} #{preview}"
        when "assistant"
          tool_str = e.tool_calls.any? ? " [#{e.tool_calls.map { |t| t["name"] }.join(", ")}]" : ""
          preview = truncate(e.content.to_s, 60)
          puts "  #{@pastel.dim("↳ #{preview}#{tool_str}")}"
        when "tool_result"
          preview = truncate(e.content.to_s, 40)
          puts "  #{@pastel.dim("  → #{e.tool_name}: #{preview}")}"
        end
      end
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
