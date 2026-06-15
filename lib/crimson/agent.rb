# frozen_string_literal: true

require "json"
require "securerandom"

module Crimson
  # Thread-safe abort signal for cancelling tool execution mid-flight.
  class AbortSignal
    def initialize
      @aborted = false
      @mutex = Mutex.new
    end

    # Mark as aborted.
    # @return [void]
    def abort!
      @mutex.synchronize { @aborted = true }
    end

    # @return [Boolean] whether abort has been requested
    def aborted?
      @mutex.synchronize { @aborted }
    end

    # Reset abort state.
    # @return [void]
    def reset
      @mutex.synchronize { @aborted = false }
    end
  end

  # Core agent loop managing conversation history, tool execution, session persistence, and event emission.
  class Agent
    # Maximum iterations per user prompt before forcing a break.
    MAX_ITERATIONS = 50
    # File name for saving/loading conversation history.
    HISTORY_FILE = ".crimson_history"

    # Keywords that signal tool usage may be needed.
    NEEDS_TOOL_PATTERNS = %w[
      read write edit create fix bug test run exec command search find
      file files directory folder install update delete remove patch
      config setup deploy build compile lint format check verify
      gem npm pip cargo bundle make git docker ls cat touch mkdir rm mv cp
      grep rg sed awk head tail wc diff code project src spec
      explain why how where when who which refactor implement
      list show look open
    ].freeze

    # Patterns that indicate a trivial greeting that doesn't need tools.
    TRIVIAL_PATTERNS = %w[hi hello hey thanks thank ok yes no bye goodbye sure].freeze

    # @return [ToolRegistry]
    # @return [Hash] token usage accumulator (prompt/completion/total)
    # @return [EventEmitter]
    # @return [SteeringManager]
    attr_reader :tool_registry, :token_usage, :events, :steering
    # @return [String, nil] current session ID
    # @return [String, nil] session working directory
    # @return [CostTracker]
    # @return [Compactor, nil]
    attr_reader :session_id, :session_cwd, :cost_tracker, :compactor
    # @return [Config]
    attr_accessor :config
    # @api private
    attr_writer :define_system_prompt

    # @param client [Client::Base]
    # @param tool_registry [ToolRegistry]
    # @param system_prompt [String]
    # @param skill_router [SkillRouter, nil]
    def initialize(client:, tool_registry:, system_prompt:, skill_router: nil)
      @client = client
      @tool_registry = tool_registry
      @system_prompt = system_prompt
      @system_prompt_builder = nil
      @skill_router = skill_router || SkillRouter.new
      @active_skills = ["coding"]
      @config = Crimson.config
      @history = []
      @events = Agent::EventEmitter.new
      @steering = Agent::SteeringManager.new
      @token_usage = { prompt: 0, completion: 0, total: 0 }
      @before_tool_call = nil
      @after_tool_call = nil
      @abort_controller = false
      @abort_signal = AbortSignal.new
      @session_manager = nil
      @session_id = nil
      @session_cwd = nil
      @last_entry_id = nil
      @session_buffer = []
      @compactor = nil
      @cost_tracker = CostTracker.new
      @cached_tool_defs = nil
      @cached_system_msg = nil
    end

    # Subscribe to an agent event.
    # @param event_type [Symbol] event type constant
    # @yield handler block
    # @return [void]
    def on(event_type, &handler)
      @events.on(event_type, &handler)
    end

    # Register a hook that runs before each tool call.
    # @yieldparam tool_call [Message::ToolCall]
    # @yieldparam args [Hash]
    # @yieldparam history [Array<Message::Base>]
    # @return [void]
    def before_tool_call(&block)
      @before_tool_call = block
    end

    # Register a hook that runs after each tool call.
    # @yieldparam tool_call [Message::ToolCall]
    # @yieldparam result [String]
    # @yieldparam is_error [Boolean]
    # @yieldparam history [Array<Message::Base>]
    # @return [void]
    def after_tool_call(&block)
      @after_tool_call = block
    end

    # Start a new session for the given working directory.
    # @param cwd [String]
    # @param session_manager [SessionManager]
    # @return [void]
    def start_session(cwd:, session_manager: SessionManager.new)
      @session_manager = session_manager
      @session_id = @session_manager.create(cwd: cwd)
      @session_cwd = cwd
      @last_entry_id = nil
    end

    # Resume an existing session by loading its history.
    # @param session_id [String]
    # @param cwd [String]
    # @param session_manager [SessionManager]
    # @return [void]
    def resume_session(session_id, cwd:, session_manager: SessionManager.new)
      @session_manager = session_manager
      entries = @session_manager.load(session_id, cwd: cwd)
      @session_id = session_id
      @session_cwd = cwd
      @history = entries.map(&:to_message).compact
      @last_entry_id = entries.last&.id
    end

    # Enable context compaction with the given client for summarization.
    # @param client [Client::Base]
    # @param max_context_tokens [Integer]
    # @param model [String, nil]
    # @param provider [String, nil]
    # @return [void]
    def enable_compaction!(client:, max_context_tokens: 100_000, model: nil, provider: nil)
      @compactor = Compactor.new(
        client: client,
        max_context_tokens: max_context_tokens,
        model: model || Crimson.config&.model,
        provider: provider || Crimson.config&.provider
      )
    end

    # Force compaction of the conversation history.
    # @return [String] status message
    def compact!
      return "Compaction not enabled" unless @compactor
      return "History too short to compact" if @history.length <= 5

      @history = @compactor.compact(@history, system_prompt: resolved_system_prompt)
      "Compacted history to #{@history.length} messages"
    end

    # Process user input through the agent loop.
    # @param user_input [String]
    # @return [void]
    def prompt(user_input)
      @history << Message::User.new(user_input)
      append_to_session(@history.last)
      @events.emit(Agent::Events::MESSAGE_START, message: @history.last)
      @events.emit(Agent::Events::MESSAGE_END, message: @history.last)
      run_loop
    end

    # Continue the agent loop after a manual break.
    # @return [void]
    def continue
      run_loop
    end

    # Inject a steering message into the current turn.
    # @param message [String]
    # @return [void]
    def steer(message)
      @steering.steer(Message::User.new(message))
    end

    # Inject a follow-up message into the current turn.
    # @param message [String]
    # @return [void]
    def follow_up(message)
      @steering.follow_up(Message::User.new(message))
    end

    # Abort the current agent execution.
    # @return [void]
    def abort!
      @abort_signal.abort!
      @abort_controller = true
    end

    # Switch to a different model, recreating the client adapter.
    # @param model_id [String]
    # @return [void]
    def switch_model(model_id)
      @config = Config.new(
        provider: @config.provider,
        model: model_id,
        api_key: @config.api_key,
        base_url: @config.base_url,
        max_tokens: @config.max_tokens,
        thinking_level: @config.thinking_level
      )
      @client = Crimson::Client.create(@config)
      @cached_tool_defs = nil
      @cached_system_msg = nil
    end

    # Reset conversation history and token usage.
    # @return [void]
    def reset
      @history.clear
      @token_usage = { prompt: 0, completion: 0, total: 0 }
      @steering.clear_all
      @cost_tracker.reset
    end

    # @return [Array<Message::Base>] a copy of the conversation history
    def history
      @history.dup
    end

    # @param new_history [Array<Message::Base>]
    def history=(new_history)
      @history = new_history.dup
    end

    # Save conversation history to a JSON file.
    # @return [String] status message
    def save_history
      data = {
        history: @history.map { |msg| serialize_message(msg) },
        token_usage: @token_usage
      }
      File.write(HISTORY_FILE, JSON.pretty_generate(data))
      "Conversation saved to #{HISTORY_FILE}"
    end

    # Load conversation history from a JSON file.
    # @return [String] status message
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

    # @api private
    def resolved_system_prompt
      @system_prompt || @system_prompt_builder&.call || ""
    end

    # @api private
    def run_loop
      @abort_controller = false
      @abort_signal.reset
      @events.emit(Agent::Events::AGENT_START)

      iterations = 0
      all_messages = []

      loop do
        iterations += 1
        break if iterations > MAX_ITERATIONS
        break if @abort_controller

        last_user_msg = @history.last&.content.to_s
        tools_invoked = last_invoked_tool_names
        new_skills = @skill_router.resolve(last_user_msg, tools_invoked: tools_invoked)
        if new_skills != @active_skills
          @active_skills = new_skills
          @cached_system_msg = nil
        end

        @events.emit(Agent::Events::TURN_START, active_skills: @active_skills)

        maybe_compact

        messages = build_messages
        tools = tools_for_message(last_user_msg)

        assistant_message, usage = RetryHandler.with_retry do
          @client.chat(messages: messages, tools: tools) do |text_chunk, _tool_event|
            if text_chunk
              @events.emit(Agent::Events::MESSAGE_UPDATE, delta: text_chunk, content_index: 0)
            end
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
          execute_tools_and_continue(assistant_message, all_messages)
        else
          @events.emit(Agent::Events::TURN_END, message: assistant_message, tool_results: [])
          break if @abort_controller

          if @steering.has_steering?
            inject_steering_messages(all_messages)
            next
          end

          if @steering.has_follow_up?
            inject_follow_up_messages(all_messages)
            next
          end

          break
        end
      end

      flush_session_buffer
      @events.emit(Agent::Events::AGENT_END, messages: all_messages)
    end

    # @api private
    def maybe_compact
      return unless @compactor && @history.length > 10 && @compactor.needs_compaction?(@history)

      @history = @compactor.compact(@history, system_prompt: resolved_system_prompt)
    end

    # @api private
    def execute_tools_and_continue(assistant_message, all_messages)
      executor = Agent::ToolExecutor.new(
        @tool_registry, @events,
        before_hook: @before_tool_call,
        after_hook: @after_tool_call,
        abort_signal: @abort_signal
      )

      results = executor.execute(assistant_message.tool_calls, @history)

      results.each do |r|
        tr = Message::ToolResult.new(
          tool_call_id: r[:tool_call].id,
          name: r[:tool_call].name,
          content: r[:result]
        )
        @history << tr
        append_to_session(tr)
        all_messages << tr
      end

      @events.emit(Agent::Events::TURN_END, message: assistant_message, tool_results: results)
      return if @abort_controller

      inject_steering_messages(all_messages) if @steering.has_steering?
    end

    # @api private
    def inject_steering_messages(all_messages)
      @steering.pop_all_steering.each do |msg|
        @history << msg
        all_messages << msg
      end
    end

    # @api private
    def inject_follow_up_messages(all_messages)
      @steering.pop_all_follow_up.each do |msg|
        @history << msg
        all_messages << msg
      end
    end

    # @api private
    def build_messages
      msgs = []
      prompt = assemble_system_prompt
      msgs << Message::System.new(prompt) unless prompt.empty?
      msgs.concat(@history)
      msgs
    end

    # @api private
    def assemble_system_prompt
      parts = []
      base = resolved_system_prompt
      parts << base unless base.empty?

      @active_skills.each do |skill_name|
        next if skill_name == "coding" && !base.empty?
        content = @skill_router.load_skill(skill_name)
        parts << content if content && !content.empty?
      end

      parts.join("\n\n")
    end

    # @api private
    def last_invoked_tool_names
      @history.reverse_each do |msg|
        next unless msg.is_a?(Message::Assistant) && msg.tool_calls&.any?
        return msg.tool_calls.map(&:name)
      end
      []
    end

    # @api private
    def provider_tool_definitions
      sdk = PROVIDERS[Crimson.config.provider.to_sym][:sdk]
      case sdk
      when :openai then @tool_registry.openai_definitions
      when :anthropic then @tool_registry.anthropic_definitions
      else []
      end
    end

    # @api private
    def track_usage(usage)
      return unless usage
      @token_usage[:prompt] += (usage[:prompt_tokens] || usage["prompt_tokens"] || 0)
      @token_usage[:completion] += (usage[:completion_tokens] || usage["completion_tokens"] || 0)
      @token_usage[:total] += (usage[:total_tokens] || usage["total_tokens"] || 0)
      @cost_tracker.track(Crimson.config.model, usage)
    end

    # @api private
    def tools_for_message(user_input)
      return cached_tool_definitions if needs_tools?(user_input)
      []
    end

    # @api private
    def cached_tool_definitions
      @cached_tool_defs ||= provider_tool_definitions
    end

    # @api private
    def needs_tools?(input)
      return true if @history.any? { |m| m.is_a?(Message::ToolResult) }

      lower = input.downcase.strip
      return false if TRIVIAL_PATTERNS.include?(lower) || lower.length < 5

      NEEDS_TOOL_PATTERNS.any? { |keyword| lower.include?(keyword) }
    end

    # @api private
    def append_to_session(message)
      return unless @session_manager && @session_id

      read_files = []
      modified_files = []

      if message.is_a?(Message::ToolResult)
        tool_name = message.name
        args = find_tool_call_args(tool_name, message.tool_call_id)
        if args
          path = args["path"] || args[:path]
          case tool_name
          when "read_file"
            read_files = [path].compact
          when "write_file", "edit_file"
            modified_files = [path].compact
          end
        end
      end

      entry = SessionEntry.from_message(message, parent_id: @last_entry_id,
                                       read_files: read_files,
                                       modified_files: modified_files)
      if message.is_a?(Message::Assistant) && @token_usage[:total] > 0
        entry.token_usage = {
          "prompt" => @token_usage[:prompt],
          "completion" => @token_usage[:completion],
          "total" => @token_usage[:total]
        }
      end
      @last_entry_id = entry.id
      @session_buffer << entry

      flush_session_buffer if @session_buffer.length >= 3
    end

    # @api private
    def find_tool_call_args(tool_name, tool_call_id)
      @history.reverse_each do |msg|
        next unless msg.is_a?(Message::Assistant) && msg.tool_calls
        tc = msg.tool_calls.find { |t| t.id == tool_call_id }
        return tc.arguments if tc
      end
      nil
    end

    # @api private
    def flush_session_buffer
      return if @session_buffer.empty?
      return unless @session_manager && @session_id

      entries = @session_buffer.dup
      @session_buffer.clear
      entries.each { |e| @session_manager.append(@session_id, cwd: @session_cwd, entry: e) }
    end

    # @api private
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

    # @api private
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
