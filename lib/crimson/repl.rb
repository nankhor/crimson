require 'reline'
require 'pastel'

module Crimson
  class Repl
    def initialize(agent)
      @agent = agent
      @pastel = Pastel.new
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
          puts @pastel.cyan("⏺ #{input}")
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
  end
end
