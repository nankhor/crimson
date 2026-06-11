require "json"
require "securerandom"

module Crimson
  class Agent
    MAX_ITERATIONS = 50
    HISTORY_FILE = ".crimson_history"

    attr_reader :tool_registry, :token_usage, :events, :steering, :session_id, :session_cwd, :cost_tracker, :compactor

    def initialize(client:, tool_registry:, system_prompt:)
      @client = client
      @tool_registry = tool_registry
      @system_prompt = system_prompt
      @history = []
      @events = Agent::EventEmitter.new
      @steering = Agent::SteeringManager.new
      @token_usage = { prompt: 0, completion: 0, total: 0 }
      @before_tool_call = nil
      @after_tool_call = nil
      @abort_controller = false
      @session_manager = nil
      @session_id = nil
      @session_cwd = nil
      @last_entry_id = nil
      @compactor = nil
      @cost_tracker = CostTracker.new
    end

    def on(event_type, &handler)
      @events.on(event_type, &handler)
    end

    def before_tool_call(&block)
      @before_tool_call = block
    end

    def after_tool_call(&block)
      @after_tool_call = block
    end

    def start_session(cwd:, session_manager: SessionManager.new)
      @session_manager = session_manager
      @session_id = @session_manager.create(cwd: cwd)
      @session_cwd = cwd
      @last_entry_id = nil
    end

    def resume_session(session_id, cwd:, session_manager: SessionManager.new)
      @session_manager = session_manager
      entries = @session_manager.load(session_id, cwd: cwd)
      @session_id = session_id
      @session_cwd = cwd
      @history = entries.map(&:to_message).compact
      @last_entry_id = entries.last&.id
    end

    def enable_compaction!(client:, max_context_tokens: 100_000)
      @compactor = Compactor.new(client: client, max_context_tokens: max_context_tokens)
    end

    def compact!
      return "Compaction not enabled" unless @compactor
      return "History too short to compact" if @history.length <= 5

      @history = @compactor.compact(@history, system_prompt: @system_prompt)
      "Compacted history to #{@history.length} messages"
    end

    def prompt(user_input)
      @history << Message::User.new(user_input)
      append_to_session(@history.last)
      @events.emit(Agent::Events::MESSAGE_START, message: @history.last)
      @events.emit(Agent::Events::MESSAGE_END, message: @history.last)
      run_loop
    end

    def continue
      run_loop
    end

    def steer(message)
      @steering.steer(Message::User.new(message))
    end

    def follow_up(message)
      @steering.follow_up(Message::User.new(message))
    end

    def abort!
      @abort_controller = true
    end

    def reset
      @history.clear
      @token_usage = { prompt: 0, completion: 0, total: 0 }
      @steering.clear_all
      @cost_tracker.reset
    end

    def history
      @history.dup
    end

    def history=(new_history)
      @history = new_history.dup
    end

    def run(user_input)
      prompt(user_input)
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

    def run_loop
      @abort_controller = false
      @events.emit(Agent::Events::AGENT_START)

      iterations = 0
      all_messages = []

      loop do
        iterations += 1
        if iterations > MAX_ITERATIONS
          break
        end

        break if @abort_controller

        @events.emit(Agent::Events::TURN_START)

        messages = build_messages

        if @compactor && @compactor.needs_compaction?(@history)
          @history = @compactor.compact(@history, system_prompt: @system_prompt)
        end

        tools = provider_tool_definitions

        assistant_message, usage = @client.chat(messages: messages, tools: tools) do |text_chunk, tool_event|
          if text_chunk
            @events.emit(Agent::Events::MESSAGE_UPDATE,
              delta: text_chunk, content_index: 0)
          end
        end

        break unless assistant_message

        @events.emit(Agent::Events::MESSAGE_START, message: assistant_message)
        @events.emit(Agent::Events::MESSAGE_END, message: assistant_message)

        track_usage(usage) if usage
        @history << assistant_message
        append_to_session(assistant_message)
        all_messages << assistant_message

        if assistant_message.tool_call?
          executor = Agent::ToolExecutor.new(
            @tool_registry, @events,
            before_hook: @before_tool_call,
            after_hook: @after_tool_call
          )

          results = executor.execute(assistant_message.tool_calls, @history)

          tool_results = results.map do |r|
            Message::ToolResult.new(
              tool_call_id: r[:tool_call].id,
              name: r[:tool_call].name,
              content: r[:result]
            )
          end

          tool_results.each do |tr|
            @history << tr
            append_to_session(tr)
            all_messages << tr
          end

          @events.emit(Agent::Events::TURN_END,
            message: assistant_message, tool_results: results)

          if @abort_controller
            break
          end

          if @steering.has_steering?
            steering_msgs = @steering.pop_all_steering
            steering_msgs.each do |msg|
              @history << msg
              all_messages << msg
            end
          end
        else
          @events.emit(Agent::Events::TURN_END,
            message: assistant_message, tool_results: [])

          if @abort_controller
            break
          end

          if @steering.has_steering?
            steering_msgs = @steering.pop_all_steering
            steering_msgs.each do |msg|
              @history << msg
              all_messages << msg
            end
            next
          end

          if @steering.has_follow_up?
            follow_up_msgs = @steering.pop_all_follow_up
            follow_up_msgs.each do |msg|
              @history << msg
              all_messages << msg
            end
            next
          end

          break
        end
      end

      @events.emit(Agent::Events::AGENT_END, messages: all_messages)
    end

    def build_messages
      msgs = []
      msgs << Message::System.new(@system_prompt) unless @system_prompt.empty?
      msgs.concat(@history)
      msgs
    end

    def provider_tool_definitions
      sdk = PROVIDERS[Crimson.config.provider.to_sym][:sdk]
      case sdk
      when :openai then @tool_registry.openai_definitions
      when :anthropic then @tool_registry.anthropic_definitions
      else []
      end
    end

    def track_usage(usage)
      return unless usage
      @token_usage[:prompt] += (usage[:prompt_tokens] || usage["prompt_tokens"] || 0)
      @token_usage[:completion] += (usage[:completion_tokens] || usage["completion_tokens"] || 0)
      @token_usage[:total] += (usage[:total_tokens] || usage["total_tokens"] || 0)
      @cost_tracker.track(Crimson.config.model, usage)
    end

    def serialize_message(msg)
      case msg
      when Message::User
        { type: "user", content: msg.content }
      when Message::Assistant
        {
          type: "assistant",
          content: msg.content,
          tool_calls: msg.tool_calls.map { |tc| { id: tc.id, name: tc.name, arguments: tc.arguments } }
        }
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

    def append_to_session(message)
      return unless @session_manager && @session_id

      entry = SessionEntry.from_message(message, parent_id: @last_entry_id)
      if message.is_a?(Message::Assistant) && @token_usage[:total] > 0
        entry.token_usage = {
          "prompt" => @token_usage[:prompt],
          "completion" => @token_usage[:completion],
          "total" => @token_usage[:total]
        }
      end
      @session_manager.append(@session_id, cwd: @session_cwd, entry: entry)
      @last_entry_id = entry.id
    end
  end
end
