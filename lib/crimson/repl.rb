# frozen_string_literal: true

require "reline"
require "pastel"
require_relative "status_bar"
require_relative "output_handler"

module Crimson
  class Repl
    def initialize(agent)
      @agent = agent
      @pastel = Pastel.new
      @status_bar = StatusBar.new(@pastel)
      @output_handler = OutputHandler.new
      @output_handler.attach(agent, @status_bar)
      setup_readline
    end

    def start
      @status_bar.start
      @status_bar.write_ln(@pastel.bold("Crimson v#{VERSION}"))
      @status_bar.write_ln(@pastel.dim("Type /help for commands, /exit to quit"))
      @status_bar.write_ln("")
      @status_bar.flush

      update_status_from_agent

      loop do
        @status_bar.handle_resize
        @status_bar.move_to_input
        input = Reline.readline("> ", true)

        break if input.nil?
        input = input.strip
        break if input == "/exit" || input == "/quit"
        next if input.empty?

        if input.start_with?("/")
          result = handle_command(input)
          break if result == :quit
        else
          @agent.prompt(input)
          update_status_from_agent
        end
      rescue Interrupt
        @status_bar.write_ln(@pastel.yellow("  cancelled."))
        @status_bar.flush
      rescue => e
        @status_bar.write_ln(@pastel.red("  error: #{e.message}"))
        @status_bar.flush
      end
    ensure
      @status_bar.stop
      puts @pastel.dim("Goodbye!")
    end

    private

    def update_status_from_agent
      usage = @agent.token_usage rescue { prompt: 0, completion: 0, total: 0 }
      cost = @agent.cost_tracker.total_cost rescue 0.0
      model = @agent.config.model rescue ""
      provider = @agent.config.provider rescue ""
      @status_bar.update(model: model, provider: provider, tokens: usage, cost: cost)
    end

    def handle_command(input)
      case input
      when "/help"
        show_help
      when "/exit", "/quit"
        :quit
      when "/clear"
        @agent.reset
        @status_bar.write_ln(@pastel.dim("  conversation cleared."))
      when "/model"
        handle_model_switch
      when "/thinking"
        handle_thinking
      when "/tools"
        @status_bar.write_ln(@pastel.bold("  tools:"))
        @agent.tool_registry.tool_names.each { |n| @status_bar.write_ln("    - #{n}") }
      when "/save"
        @status_bar.write_ln("  #{@agent.save_history}")
      when "/load"
        @status_bar.write_ln("  #{@agent.load_history}")
      when "/usage"
        show_usage
      when "/sessions"
        handle_sessions
      when "/name"
        @status_bar.write_ln(@pastel.dim("  usage: /name <session name>"))
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
          @status_bar.write_ln(@pastel.yellow("  unknown: #{input}. type /help"))
        end
      end
      @status_bar.flush
      nil
    end

    def show_help
      lines = [
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
      lines.each { |l| @status_bar.write_ln(@pastel.dim(l)) }
    end

    def show_usage
      usage = @agent.token_usage
      cost = @agent.cost_tracker.total_cost
      @status_bar.write_ln("  prompt:     #{usage[:prompt]}")
      @status_bar.write_ln("  completion: #{usage[:completion]}")
      @status_bar.write_ln("  total:      #{usage[:total]}")
      @status_bar.write_ln("  cost:       $#{format('%.4f', cost)}") if cost > 0
    end

    def handle_sessions
      return @status_bar.write_ln(@pastel.dim("  no active session.")) unless @agent.session_id

      manager = SessionManager.new
      sessions = manager.list(cwd: Dir.pwd)
      if sessions.empty?
        @status_bar.write_ln(@pastel.dim("  no sessions found."))
      else
        sessions.each do |s|
          current = s.id == @agent.session_id ? " (current)" : ""
          name_str = s.name ? "[#{s.name}] " : ""
          preview = s.preview || "(no preview)"
          @status_bar.write_ln("  #{@pastel.cyan(s.id[0..7])} #{name_str}#{preview} #{s.last_timestamp}#{current}")
        end
      end
    end

    def handle_model_switch
      config = @agent.config || Crimson.config
      @status_bar.write_ln(@pastel.dim("  current: #{PROVIDERS[config.provider.to_sym][:name]} / #{config.model}"))
      @status_bar.flush

      begin
        prompt = TTY::Prompt.new
        models = fetch_available_models(config)
        if models.empty?
          @status_bar.write_ln(@pastel.yellow("  could not fetch model list."))
          return
        end
        selected = prompt.select("select model:", models.map { |m| { name: m, value: m } })
        @agent.switch_model(selected)
        @agent.config.save
        update_status_from_agent
        @status_bar.write_ln(@pastel.dim("  switched to: #{selected}"))
      rescue => e
        @status_bar.write_ln(@pastel.red("  error: #{e.message}"))
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
      @status_bar.write_ln(@pastel.dim("  current thinking level: #{current}"))
      @status_bar.flush

      begin
        prompt = TTY::Prompt.new
        level = prompt.select("thinking level:", %w[off low medium high].map { |l| { name: l, value: l } })
        config.thinking_level = level
        config.save
        @agent.config = config
        @status_bar.write_ln(@pastel.dim("  thinking level set to: #{level}"))
      rescue => e
        @status_bar.write_ln(@pastel.red("  error: #{e.message}"))
      end
    end

    def handle_session_info
      return @status_bar.write_ln(@pastel.dim("  no active session.")) unless @agent.session_id

      manager = SessionManager.new
      header = manager.load_header(@agent.session_id, cwd: Dir.pwd)
      entries = manager.load(@agent.session_id, cwd: Dir.pwd)
      usage = @agent.token_usage
      cost = @agent.cost_tracker.total_cost

      @status_bar.write_ln("  id:       #{@agent.session_id}")
      @status_bar.write_ln("  name:     #{header&.dig('name') || '(unnamed)'}")
      @status_bar.write_ln("  entries:  #{entries.length}")
      @status_bar.write_ln("  tokens:   #{usage[:total]}")
      @status_bar.write_ln("  cost:     $#{format('%.4f', cost)}") if cost > 0
    end

    def handle_name_set(name)
      return @status_bar.write_ln(@pastel.dim("  no active session.")) unless @agent.session_id
      return @status_bar.write_ln(@pastel.dim("  usage: /name <session name>")) if name.empty?

      manager = SessionManager.new
      manager.set_name(@agent.session_id, cwd: Dir.pwd, name: name)
      @status_bar.write_ln(@pastel.dim("  session name set to: #{name}"))
    end

    def handle_fork
      return @status_bar.write_ln(@pastel.dim("  no active session.")) unless @agent.session_id

      manager = SessionManager.new
      last_id = @agent.instance_variable_get(:@last_entry_id)
      new_id = manager.fork(@agent.session_id, cwd: Dir.pwd, from_entry_id: last_id)
      @agent.resume_session(new_id, cwd: Dir.pwd, session_manager: manager)
      @status_bar.write_ln(@pastel.dim("  forked to session: #{new_id[0..7]}"))
    end

    def handle_tree
      return @status_bar.write_ln(@pastel.dim("  no active session.")) unless @agent.session_id

      manager = SessionManager.new
      entries = manager.load(@agent.session_id, cwd: Dir.pwd)
      entries.each do |e|
        case e.role
        when "user"
          @status_bar.write_ln("  * #{truncate(e.content.to_s, 60)}")
        when "assistant"
          tool_str = e.tool_calls.any? ? " [#{e.tool_calls.map { |t| t["name"] }.join(", ")}]" : ""
          @status_bar.write_ln("    #{truncate(e.content.to_s, 60)}#{tool_str}")
        when "tool_result"
          @status_bar.write_ln("      -> #{e.tool_name}: #{truncate(e.content.to_s, 40)}")
        end
      end
    end

    def handle_compact
      if @agent.compactor
        result = @agent.compact!
        @status_bar.write_ln(@pastel.dim("  #{result}"))
      else
        @status_bar.write_ln(@pastel.dim("  compaction not enabled."))
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
