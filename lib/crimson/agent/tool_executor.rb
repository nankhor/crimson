# frozen_string_literal: true

require "thread"

module Crimson
  class Agent
    # Executes tool calls with parallel/sequential modes, hooks, and abort support.
    class ToolExecutor
      # @param tool_registry [ToolRegistry]
      # @param events [EventEmitter]
      # @param before_hook [Proc, nil]
      # @param after_hook [Proc, nil]
      # @param abort_signal [AbortSignal, nil]
      def initialize(tool_registry, events, before_hook: nil, after_hook: nil, abort_signal: nil)
        @tool_registry = tool_registry
        @events = events
        @before_hook = before_hook
        @after_hook = after_hook
        @abort_signal = abort_signal
      end

      # Execute a list of tool calls.
      # Tools marked as sequential run one at a time; others run in parallel.
      # @param tool_calls [Array<Message::ToolCall>]
      # @param history [Array<Message::Base>]
      # @return [Array<Hash>] results with keys :tool_call, :result, :is_error
      def execute(tool_calls, history)
        sequential = tool_calls.any? { |tc| tool_sequential?(tc) }

        if sequential
          execute_sequential(tool_calls, history)
        else
          execute_parallel(tool_calls, history)
        end
      end

      private

      # @api private
      def execute_parallel(tool_calls, history)
        results = {}
        mutex = Mutex.new

        threads = tool_calls.map do |tc|
          Thread.new do
            result = execute_single(tc, history)
            mutex.synchronize { results[tc.id] = result }
          end
        end

        threads.each(&:join)

        tool_calls.map { |tc| results[tc.id] }
      end

      # @api private
      def execute_sequential(tool_calls, history)
        tool_calls.map { |tc| execute_single(tc, history) }
      end

      # @api private
      def execute_single(tc, history)
        args_display = tc.arguments.is_a?(Hash) ? tc.arguments : tc.arguments.to_s
        @events.emit(Events::TOOL_EXECUTION_START,
          tool_call_id: tc.id, tool_name: tc.name, args: args_display)

        if @before_hook
          hook_result = @before_hook.call(tool_call: tc, args: tc.arguments, history: history)
          if hook_result.is_a?(Hash) && hook_result[:block]
            result = "Blocked: #{hook_result[:reason]}"
            @events.emit(Events::TOOL_EXECUTION_END,
              tool_call_id: tc.id, result: result, is_error: true)
            return { tool_call: tc, result: result, is_error: true }
          end
        end

        if tc.name == "run_command"
          tool = @tool_registry.lookup("run_command")
          if tool
            tool.on_update = -> (cmd, elapsed, bytes) {
              @events.emit(Events::TOOL_EXECUTION_UPDATE,
                tool_call_id: tc.id, tool_name: tc.name,
                partial_result: "running (#{elapsed.round(1)}s, #{bytes} bytes)")
            }
          end
        end

        result = @tool_registry.execute(tc.name, tc.arguments, abort_signal: @abort_signal)
        is_error = result.is_a?(String) && result.start_with?("Error")

        if @after_hook
          hook_result = @after_hook.call(
            tool_call: tc, result: result, is_error: is_error, history: history
          )
          if hook_result.is_a?(Hash)
            result = hook_result[:result] if hook_result.key?(:result)
          end
        end

        @events.emit(Events::TOOL_EXECUTION_END,
          tool_call_id: tc.id, result: result, is_error: is_error)

        { tool_call: tc, result: result, is_error: is_error }
      end

      # @api private
      def tool_sequential?(tc)
        tool = @tool_registry.lookup(tc.name)
        return false unless tool
        tool.const_defined?(:EXECUTION_MODE) && tool::EXECUTION_MODE == :sequential
      end
    end
  end
end
