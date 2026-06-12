# frozen_string_literal: true

require "pastel"

module Crimson
  class Repl
    def initialize(agent)
      @agent = agent
      @pastel = Pastel.new
      @tui = Tui.new
      @output_handler = OutputHandler.new
      @output_handler.attach(agent, @tui)
      @agent_thread = nil
      @agent_running = false
    end

    def start
      @tui.run do
        @tui.insert_content("**Crimson v#{VERSION}** — Type `/help` for commands, Ctrl+C to cancel")

        loop do
          result = input_loop
          break if result == :quit

          if result[:command]
            break if handle_command(result[:command]) == :quit
          elsif result[:input]
            run_agent(result[:input])
          end
        end
      end
    end

    private

    def input_loop
      loop do
        event = @tui.poll_event(timeout: 0.05)

        if event && event.respond_to?(:code)
          result = @tui.handle_key(event)
          return result if result
        end

        @tui.draw_frame
      end
    end

    def run_agent(input)
      @agent_running = true
      @tui.insert_content("  \e[1m#{input}\e[0m")

      @agent_thread = Thread.new do
        begin
          @agent.prompt(input)
        rescue Interrupt
          @tui.insert_content("\n  cancelled.")
        rescue => e
          @tui.insert_content("\n  error: #{e.message}")
        ensure
          @agent_running = false
        end
      end

      while @agent_running
        event = @tui.poll_event(timeout: 0.05)
        if event && event.respond_to?(:code) && event.ctrl? && event.code == "c"
          @agent_thread.kill
          @tui.insert_content("\n  cancelled.")
          @agent_running = false
          @tui.hide_loading
          @tui.update_status(status: :idle)
        end
        @tui.draw_frame
      end

      @agent_thread.join
      @agent_thread = nil
      @tui.draw_frame
    end

    def handle_command(input)
      case input
      when "/help"
        show_help
      when "/exit", "/quit"
        :quit
      when "/clear"
        @agent.reset
        @tui.insert_content("  conversation cleared.")
      when "/model"
        handle_model_switch
      when "/thinking"
        handle_thinking
      when "/tools"
        @agent.tool_registry.tool_names.each { |n| @tui.insert_content("  - #{n}") }
      when "/save"
        @tui.insert_content("  #{@agent.save_history}")
      when "/load"
        @tui.insert_content("  #{@agent.load_history}")
      when "/usage"
        show_usage
      when "/sessions"
        handle_sessions
      when "/name"
        @tui.insert_content("  usage: /name <session name>")
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
          @tui.insert_content("  unknown command: #{input}. type /help")
        end
      end
      nil
    end

    def show_help
      lines = [
        "  commands:",
        "  /help       show this message",
        "  /clear      clear conversation",
        "  /model      switch model",
        "  /thinking   set thinking level",
        "  /tools      list tools",
        "  /save       save conversation",
        "  /load       load conversation",
        "  /usage      token usage",
        "  /sessions   list sessions",
        "  /name       set session name",
        "  /session    session info",
        "  /fork       fork session",
        "  /tree       conversation tree",
        "  /compact    compact history",
        "  /exit       exit"
      ]
      lines.each { |l| @tui.insert_content(l) }
    end

    def show_usage
      usage = @agent.token_usage
      cost = @agent.cost_tracker.total_cost
      @tui.insert_content("  tokens: #{usage[:prompt]}↑ #{usage[:completion]}↓ = #{usage[:total]}")
      @tui.insert_content("  cost: $#{format('%.4f', cost)}") if cost > 0
    end

    def handle_sessions
      return @tui.insert_content("  no active session.") unless @agent.session_id

      manager = SessionManager.new
      sessions = manager.list(cwd: Dir.pwd)
      if sessions.empty?
        @tui.insert_content("  no sessions found.")
      else
        sessions.each do |s|
          current = s.id == @agent.session_id ? " (current)" : ""
          name_str = s.name ? "[#{s.name}] " : ""
          preview = s.preview || "(no preview)"
          @tui.insert_content("  #{s.id[0..7]} #{name_str}#{preview} #{s.last_timestamp}#{current}")
        end
      end
    end

    def handle_model_switch
      config = @agent.config || Crimson.config
      @tui.insert_content("  current: #{PROVIDERS[config.provider.to_sym][:name]} / #{config.model}")

      begin
        prompt = TTY::Prompt.new
        models = fetch_available_models(config)
        if models.empty?
          @tui.insert_content("  could not fetch model list.")
          return
        end
        selected = prompt.select("select model:", models.map { |m| { name: m, value: m } })
        @agent.switch_model(selected)
        @agent.config.save
        @tui.insert_content("  switched to: #{selected}")
      rescue => e
        @tui.insert_content("  error: #{e.message}")
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
      @tui.insert_content("  current thinking level: #{current}")

      begin
        prompt = TTY::Prompt.new
        level = prompt.select("thinking level:", %w[off low medium high].map { |l| { name: l, value: l } })
        config.thinking_level = level
        config.save
        @agent.config = config
        @tui.insert_content("  thinking level set to: #{level}")
      rescue => e
        @tui.insert_content("  error: #{e.message}")
      end
    end

    def handle_session_info
      return @tui.insert_content("  no active session.") unless @agent.session_id

      manager = SessionManager.new
      header = manager.load_header(@agent.session_id, cwd: Dir.pwd)
      entries = manager.load(@agent.session_id, cwd: Dir.pwd)
      usage = @agent.token_usage
      cost = @agent.cost_tracker.total_cost

      @tui.insert_content("  id: #{@agent.session_id}")
      @tui.insert_content("  name: #{header&.dig('name') || '(unnamed)'}")
      @tui.insert_content("  entries: #{entries.length}")
      @tui.insert_content("  tokens: #{usage[:total]}")
      @tui.insert_content("  cost: $#{format('%.4f', cost)}") if cost > 0
    rescue => e
      @tui.insert_content("  error: #{e.message}")
    end

    def handle_name_set(name)
      return @tui.insert_content("  no active session.") unless @agent.session_id
      return @tui.insert_content("  usage: /name <session name>") if name.empty?

      manager = SessionManager.new
      manager.set_name(@agent.session_id, cwd: Dir.pwd, name: name)
      @tui.insert_content("  session name set to: #{name}")
    end

    def handle_fork
      return @tui.insert_content("  no active session.") unless @agent.session_id

      manager = SessionManager.new
      last_id = @agent.instance_variable_get(:@last_entry_id)
      new_id = manager.fork(@agent.session_id, cwd: Dir.pwd, from_entry_id: last_id)
      @agent.resume_session(new_id, cwd: Dir.pwd, session_manager: manager)
      @tui.insert_content("  forked to session: #{new_id[0..7]}")
    end

    def handle_tree
      return @tui.insert_content("  no active session.") unless @agent.session_id

      manager = SessionManager.new
      entries = manager.load(@agent.session_id, cwd: Dir.pwd)
      entries.each do |e|
        case e.role
        when "user"
          @tui.insert_content("  * #{truncate(e.content.to_s, 60)}")
        when "assistant"
          tool_str = e.tool_calls.any? ? " [#{e.tool_calls.map { |t| t["name"] }.join(", ")}]" : ""
          @tui.insert_content("    #{truncate(e.content.to_s, 60)}#{tool_str}")
        when "tool_result"
          @tui.insert_content("      -> #{e.tool_name}: #{truncate(e.content.to_s, 40)}")
        end
      end
    end

    def handle_compact
      if @agent.compactor
        result = @agent.compact!
        @tui.insert_content("  #{result}")
      else
        @tui.insert_content("  compaction not enabled.")
      end
    end

    def truncate(text, max_len)
      return "" if text.nil?
      cleaned = text.gsub("\n", "\\n")
      cleaned.length > max_len ? "#{cleaned[0...max_len]}..." : cleaned
    end
  end
end
