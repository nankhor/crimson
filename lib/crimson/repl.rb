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
      @tui = @output_handler.tui
      setup_readline
    end

    def start
      @output_handler.start

      # Show welcome message via TUI
      @tui.append_markdown("**Crimson v#{VERSION}**")
      @tui.append_markdown("Type `/help` for commands, `/exit` to quit")
      @tui.request_render

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
      rescue Interrupt
        @tui.append_markdown("*Operation cancelled by user.*")
        @tui.request_render
      rescue => e
        @tui.append_markdown("**Error:** #{e.message}")
        @tui.request_render
      end

      @output_handler.stop
      @tui.append_markdown("*Goodbye!*")
      @tui.request_render
    end

    private

    def handle_command(input)
      case input
      when "/help"
        show_help
      when "/clear"
        @agent.reset
        @tui.clear_markdown
        @tui.clear_tool_executions
        @tui.append_markdown("*Conversation cleared.*")
        @tui.request_render
      when "/model"
        handle_model_switch
      when "/thinking"
        handle_thinking
      when "/tools"
        show_tools
      when "/save"
        @tui.append_markdown(@agent.save_history)
        @tui.request_render
      when "/load"
        @tui.append_markdown(@agent.load_history)
        @tui.request_render
      when "/usage"
        show_usage
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
        handle_compact
      else
        if input.start_with?("/name ")
          handle_name_set(input[6..].strip)
        else
          @tui.append_markdown("*Unknown command: #{input}. Type `/help` for commands.*")
          @tui.request_render
        end
      end
    end

    def show_help
      help_text = <<~HELP
        **Commands:**
        - `/help`       Show help message
        - `/clear`      Clear conversation history
        - `/model`      Switch model (interactive selector)
        - `/thinking`   Set thinking level (off/low/medium/high)
        - `/tools`      List available tools
        - `/save`       Save conversation to file
        - `/load`       Load conversation from file
        - `/usage`      Show token usage and cost
        - `/sessions`   List sessions for current directory
        - `/name`       Set session name
        - `/session`    Show session info
        - `/fork`       Fork current session into new branch
        - `/tree`       Show conversation tree
        - `/compact`    Compact conversation history
        - `/exit`       Exit crimson
      HELP
      @tui.append_markdown(help_text)
      @tui.request_render
    end

    def show_tools
      tools = @agent.tool_registry.tool_names.map { |n| "- #{n}" }.join("\n")
      @tui.append_markdown("**Available tools:**\n#{tools}")
      @tui.request_render
    end

    def show_usage
      usage = @agent.token_usage
      cost = @agent.cost_tracker.total_cost
      text = <<~USAGE
        **Token usage:**
        - Prompt:     #{usage[:prompt]}
        - Completion: #{usage[:completion]}
        - Total:      #{usage[:total]}
      USAGE
      text += "- Cost:       $#{format('%.4f', cost)}" if cost > 0
      @tui.append_markdown(text)
      @tui.request_render
    end

    def handle_sessions
      unless @agent.session_id
        @tui.append_markdown("*No active session.*")
        @tui.request_render
        return
      end

      manager = SessionManager.new
      sessions = manager.list(cwd: Dir.pwd)
      if sessions.empty?
        @tui.append_markdown("*No sessions found.*")
      else
        lines = ["**Sessions:**"]
        sessions.each do |s|
          current = s.id == @agent.session_id ? " (current)" : ""
          name_str = s.name ? "[#{s.name}] " : ""
          preview = s.preview || "(no preview)"
          lines << "- `#{s.id[0..7]}` #{name_str}#{preview} #{s.last_timestamp}#{current}"
        end
        @tui.append_markdown(lines.join("\n"))
      end
      @tui.request_render
    end

    def handle_model_switch
      config = @agent.config || Crimson.config
      @tui.append_markdown("*Current: #{PROVIDERS[config.provider.to_sym][:name]} / #{config.model}*")

      begin
        prompt = TTY::Prompt.new
        models = fetch_available_models(config)
        if models.empty?
          @tui.append_markdown("*Could not fetch model list. Showing current model only.*")
          @tui.request_render
          return
        end

        selected = prompt.select("Select model:", models.map { |m| { name: m, value: m } })
        @agent.switch_model(selected)
        @agent.config.save
        @tui.append_markdown("*Switched to: #{selected}*")
      rescue => e
        @tui.append_markdown("**Error switching model:** #{e.message}")
      end
      @tui.request_render
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
      @tui.append_markdown("*Current thinking level: #{current}*")

      begin
        prompt = TTY::Prompt.new
        level = prompt.select("Thinking level:", %w[off low medium high].map { |l| { name: l, value: l } })
        config.thinking_level = level
        config.save
        @agent.config = config
        @tui.append_markdown("*Thinking level set to: #{level}*")
      rescue => e
        @tui.append_markdown("**Error setting thinking level:** #{e.message}")
      end
      @tui.request_render
    end

    def handle_name
      unless @agent.session_id
        @tui.append_markdown("*No active session.*")
        @tui.request_render
        return
      end
      @tui.append_markdown("*Usage: /name <session name>*")
      @tui.request_render
    end

    def handle_name_set(name)
      unless @agent.session_id
        @tui.append_markdown("*No active session.*")
        @tui.request_render
        return
      end
      if name.empty?
        @tui.append_markdown("*Usage: /name <session name>*")
        @tui.request_render
        return
      end

      manager = SessionManager.new
      manager.set_name(@agent.session_id, cwd: Dir.pwd, name: name)
      @tui.append_markdown("*Session name set to: #{name}*")
      @tui.request_render
    end

    def handle_session_info
      unless @agent.session_id
        @tui.append_markdown("*No active session.*")
        @tui.request_render
        return
      end

      manager = SessionManager.new
      header = manager.load_header(@agent.session_id, cwd: Dir.pwd)
      entries = manager.load(@agent.session_id, cwd: Dir.pwd)

      usage = @agent.token_usage
      cost = @agent.cost_tracker.total_cost

      text = <<~INFO
        **Session info:**
        - ID:       #{@agent.session_id}
        - Name:     #{header&.dig('name') || '(unnamed)'}
        - Created:  #{header&.dig('timestamp')}
        - CWD:      #{@agent.session_cwd}
        - Entries:  #{entries.length}
        - Tokens:   #{usage[:total]} (#{usage[:prompt]} prompt + #{usage[:completion]} completion)
      INFO
      text += "- Cost:     $#{format('%.4f', cost)}" if cost > 0

      @tui.append_markdown(text)
      @tui.request_render
    end

    def handle_fork
      unless @agent.session_id
        @tui.append_markdown("*No active session to fork.*")
        @tui.request_render
        return
      end

      manager = SessionManager.new
      last_id = @agent.instance_variable_get(:@last_entry_id)
      new_id = manager.fork(@agent.session_id, cwd: Dir.pwd, from_entry_id: last_id)
      @agent.resume_session(new_id, cwd: Dir.pwd, session_manager: manager)
      @tui.append_markdown("*Forked to new session: #{new_id[0..7]}*")
      @tui.request_render
    end

    def handle_tree
      unless @agent.session_id
        @tui.append_markdown("*No active session.*")
        @tui.request_render
        return
      end

      manager = SessionManager.new
      entries = manager.load(@agent.session_id, cwd: Dir.pwd)
      lines = entries.map do |e|
        case e.role
        when "user"
          preview = truncate(e.content.to_s, 60)
          "- **#{preview}**"
        when "assistant"
          tool_str = e.tool_calls.any? ? " [#{e.tool_calls.map { |t| t["name"] }.join(", ")}]" : ""
          preview = truncate(e.content.to_s, 60)
          "  - #{preview}#{tool_str}"
        when "tool_result"
          preview = truncate(e.content.to_s, 40)
          "    - #{e.tool_name}: #{preview}"
        end
      end

      @tui.append_markdown(lines.join("\n"))
      @tui.request_render
    end

    def truncate(text, max_len)
      return "" if text.nil?
      cleaned = text.gsub("\n", "\\n")
      cleaned.length > max_len ? "#{cleaned[0...max_len]}..." : cleaned
    end

    def handle_compact
      if @agent.compactor
        result = @agent.compact!
        @tui.append_markdown("*#{result}*")
      else
        @tui.append_markdown("*Compaction not enabled.*")
      end
      @tui.request_render
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
