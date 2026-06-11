require 'json'
require 'pastel'

module Crimson
  class Agent
    MAX_ITERATIONS = 50
    HISTORY_FILE = ".crimson_history"

    attr_reader :tool_registry, :token_usage

    def initialize(client:, tool_registry:, system_prompt:)
      @client = client
      @tool_registry = tool_registry
      @system_prompt = system_prompt
      @history = []
      @pastel = Pastel.new
      @token_usage = { prompt: 0, completion: 0, total: 0 }
    end

    def run(user_input)
      @history << Message::User.new(user_input)

      iterations = 0

      loop do
        iterations += 1
        if iterations > MAX_ITERATIONS
          puts @pastel.yellow("\nMax iterations (#{MAX_ITERATIONS}) reached. Stopping.")
          break
        end

        messages = build_messages
        tools = provider_tool_definitions

        response, usage = @client.chat(messages: messages, tools: tools) do |text_chunk, tool_event|
          if text_chunk
            print text_chunk
            $stdout.flush
          elsif tool_event
            print_tool_call(tool_event)
          end
        end

        track_usage(usage) if usage
        @history << response

        if response.tool_call?
          puts if response.content && !response.content.empty?
          execute_tool_calls(response)
        else
          print_usage(usage)
          puts "\n"
          break
        end
      end
    end

    def reset
      @history.clear
      @token_usage = { prompt: 0, completion: 0, total: 0 }
    end

    def save_history
      data = {
        history: @history.map { |msg| serialize_message(msg) },
        token_usage: @token_usage
      }
      File.write(HISTORY_FILE, JSON.pretty_generate(data))
      "Conversation saved to #{HISTORY_FILE}"
    end

    def load_history
      return "No saved conversation found." unless File.exist?(HISTORY_FILE)

      data = JSON.parse(File.read(HISTORY_FILE), symbolize_names: true)
      @history = data[:history].map { |msg| deserialize_message(msg) }.compact
      @token_usage = data[:token_usage] || { prompt: 0, completion: 0, total: 0 }
      "Loaded #{@history.length} messages"
    rescue => e
      "Error loading history: #{e.message}"
    end

    private

    def build_messages
      msgs = []
      msgs << Message::System.new(@system_prompt) unless @system_prompt.empty?
      msgs.concat(@history)
      msgs
    end

    def provider_tool_definitions
      sdk = PROVIDERS[Crimson.config.provider.to_sym][:sdk]

      case sdk
      when :openai
        @tool_registry.openai_definitions
      when :anthropic
        @tool_registry.anthropic_definitions
      else
        []
      end
    end

    def execute_tool_calls(response)
      response.tool_calls.each do |tc|
        result = @tool_registry.execute(tc.name, tc.arguments)
        puts @pastel.dim("  -> #{truncate(result, 200)}")
        @history << Message::ToolResult.new(
          tool_call_id: tc.id,
          name: tc.name,
          content: result
        )
      end
    end

    def track_usage(usage)
      return unless usage
      @token_usage[:prompt] += (usage[:prompt_tokens] || usage["prompt_tokens"] || 0)
      @token_usage[:completion] += (usage[:completion_tokens] || usage["completion_tokens"] || 0)
      @token_usage[:total] += (usage[:total_tokens] || usage["total_tokens"] || 0)
    end

    def print_usage(usage)
      return unless usage

      prompt = usage[:prompt_tokens] || usage["prompt_tokens"] || 0
      completion = usage[:completion_tokens] || usage["completion_tokens"] || 0

      puts @pastel.dim("\n  tokens: #{prompt} prompt + #{completion} completion = #{prompt + completion} total")
    end

    def print_tool_call(tool_event)
      name = tool_event[:name]
      args = tool_event[:arguments]

      display = begin
        parsed = args.is_a?(String) ? JSON.parse(args) : args
        parsed.map { |k, v| "#{k}: #{truncate(v.to_s, 50)}" }.join(", ")
      rescue
        truncate(args.to_s, 80)
      end

      puts @pastel.cyan("  #{name}(#{display})")
    end

    def truncate(text, max_len)
      return "" if text.nil?
      cleaned = text.gsub("\n", "\\n")
      cleaned.length > max_len ? "#{cleaned[0...max_len]}..." : cleaned
    end

    def serialize_message(msg)
      case msg
      when Message::User
        { type: "user", content: msg.content }
      when Message::Assistant
        { type: "assistant", content: msg.content, tool_calls: msg.tool_calls.map { |tc| { id: tc.id, name: tc.name, arguments: tc.arguments } } }
      when Message::ToolResult
        { type: "tool_result", tool_call_id: msg.tool_call_id, name: msg.name, content: msg.content }
      end
    end

    def deserialize_message(data)
      case data[:type]
      when "user"
        Message::User.new(data[:content])
      when "assistant"
        tcs = (data[:tool_calls] || []).map do |tc|
          Message::ToolCall.new(id: tc[:id], name: tc[:name], arguments: tc[:arguments])
        end
        Message::Assistant.new(content: data[:content], tool_calls: tcs)
      when "tool_result"
        Message::ToolResult.new(tool_call_id: data[:tool_call_id], name: data[:name], content: data[:content])
      end
    end
  end
end
