require "reline"
require "pastel"

module Crimson
  class Repl
    def initialize(agent)
      @agent = agent
      @pastel = Pastel.new
      @spinner_active = false
      @first_token_received = false
      setup_event_handlers
    end

    def start
      $stdout.sync = true
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
        $stdout.print(delta)
        $stdout.flush
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

      @agent.on(Agent::Events::TURN_START) do
        unless @first_token_received
          start_spinner
        end
      end

      @agent.on(Agent::Events::AGENT_END) do
        stop_spinner
        usage = @agent.token_usage
        if usage[:total] > 0
          puts @pastel.dim("\n  tokens: #{usage[:prompt]} prompt + #{usage[:completion]} completion = #{usage[:total]} total")
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

    def handle_command(input)
      case input
      when "/help"
        puts @pastel.bold("Commands:")
        puts "  /help    Show help message"
        puts "  /clear   Clear conversation history"
        puts "  /model   Show current model"
        puts "  /tools   List available tools"
        puts "  /save    Save conversation to file"
        puts "  /load    Load conversation from file"
        puts "  /usage   Show token usage"
        puts "  /exit    Exit crimson"
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
  end
end
