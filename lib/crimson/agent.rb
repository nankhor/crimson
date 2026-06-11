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
      @cached_tools = nil
    end

    def run(user_input)
      @history << Message::User.new(user_input)

      iterations = 0

      loop do
        iterations += 1
        if iterations > MAX_ITERATIONS
          render_error("Max iterations (#{MAX_ITERATIONS}) reached. Stopping.")
          break
        end

        messages = build_messages
        tools = provider_tool_definitions

        streamed_content = false
        current_text = ""

        response, usage = @client.chat(messages: messages, tools: tools) do |text_chunk, tool_event|
          if text_chunk
            current_text << text_chunk
            render_streaming(text_chunk)
            streamed_content = true
          elsif tool_event
            render_tool_call_from_event(tool_event)
          end
        end

        track_usage(usage) if usage
        @history << response

        # Render content if it wasn't streamed (e.g., error messages)
        if response.content && !response.content.empty? && !streamed_content
          render_agent_text(response.content)
        end

        if response.tool_call?
          execute_tool_calls(response)
        else
          render_usage(usage)
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
      @cached_tools ||= begin
        sdk = PROVIDERS[Crimson.config.provider.to_sym][:sdk]
        case sdk
        when :openai then @tool_registry.openai_definitions
        when :anthropic then @tool_registry.anthropic_definitions
        else []
        end
      end
    end

    def execute_tool_calls(response)
      response.tool_calls.each do |tc|
        result = @tool_registry.execute(tc.name, tc.arguments)
        render_tool_result(tc.name, result)
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

    def render_streaming(text)
      $stdout.print(text)
      $stdout.flush
    end

    def render_agent_text(text)
      puts text
    end

    def render_tool_call_from_event(tool_event)
      name = tool_event[:name]
      args = tool_event[:arguments]
      path = extract_path(args)
      print_tool_call_fallback(name, path)
    end

    def render_tool_result(name, result)
      if result.include?("--- ") && result.include?("+++ ")
        puts result
      else
        truncated = truncate(result, 200)
        puts @pastel.dim("  -> #{truncated}")
      end
    end

    def render_usage(usage)
      return unless usage
      prompt = usage[:prompt_tokens] || usage["prompt_tokens"] || 0
      completion = usage[:completion_tokens] || usage["completion_tokens"] || 0
      total = prompt + completion
      puts @pastel.dim("\n  tokens: #{prompt} prompt + #{completion} completion = #{total} total")
    end

    def render_error(message)
      puts @pastel.red(message)
    end

    def print_tool_call_fallback(name, path)
      write_tools = ["write_file", "edit_file", "run_command"]
      is_write = write_tools.include?(name)

      if path
        if is_write
          puts @pastel.bold.green("  #{name}(#{path})")
        else
          puts @pastel.bold.red("  #{name}(#{path})")
        end
      else
        if is_write
          puts @pastel.bold.green("  #{name}")
        else
          puts @pastel.bold.cyan("  #{name}")
        end
      end
    end

    def print_tool_result_fallback(name, result)
      if result.include?("--- ") && result.include?("+++ ")
        puts result
      else
        truncated = truncate(result, 200)
        puts @pastel.dim("  -> #{truncated}")
      end
    end

    def extract_path(args)
      parsed = if args.is_a?(String)
                 JSON.parse(args) rescue {}
               else
                 args
               end
      parsed["path"] || parsed[:path]
    rescue
      nil
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
