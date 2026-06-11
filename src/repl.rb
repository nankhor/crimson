require 'reline'
require 'pastel'

module Crimson
  class Repl
    def initialize(agent)
      @agent = agent
      @pastel = Pastel.new
    end

    def start
      print_banner

      loop do
        input = Reline.readmultiline("crimson> ", false) do |multiline_input|
          true
        end

        break if input.nil?
        input = input.strip
        break if input == "/exit" || input == "/quit"
        next if input.empty?

        if input.start_with?("/")
          handle_command(input)
        else
          begin
            @agent.run(input)
          rescue => e
            puts @pastel.red("Error: #{e.message}")
          end
        end
      end

      puts @pastel.dim("Goodbye!")
    end

    private

    def print_banner
      puts @pastel.bold("Crimson v#{VERSION}")
      puts @pastel.dim("Type /help for commands, /exit to quit")
      puts
    end

    def handle_command(input)
      case input
      when "/help"
        puts <<~HELP
          Commands:
            /help    - Show this help message
            /exit    - Exit crimson
            /quit    - Exit crimson
            /clear   - Clear conversation history
            /model   - Show current model
            /tools   - List available tools
            /save    - Save conversation to file
            /load    - Load conversation from file
            /usage   - Show total token usage
        HELP
      when "/clear"
        @agent.reset
        puts @pastel.dim("Conversation cleared.")
      when "/model"
        config = Crimson.config
        puts "Provider: #{PROVIDERS[config.provider.to_sym][:name]}"
        puts "Model: #{config.model}"
      when "/tools"
        puts "Available tools:"
        puts @agent.tool_registry.tool_names.map { |n| "  - #{n}" }.join("\n")
      when "/save"
        puts @agent.save_history
      when "/load"
        puts @agent.load_history
      when "/usage"
        usage = @agent.token_usage
        puts "Token usage this session:"
        puts "  Prompt:     #{usage[:prompt]}"
        puts "  Completion: #{usage[:completion]}"
        puts "  Total:      #{usage[:total]}"
      else
        puts @pastel.yellow("Unknown command: #{input}. Type /help for available commands.")
      end
    end
  end
end
