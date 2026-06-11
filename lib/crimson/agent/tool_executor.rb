require "thread"

module Crimson
  class Agent
    class ToolExecutor
      def initialize(tool_registry, events, before_hook: nil, after_hook: nil)
        @tool_registry = tool_registry
        @events = events
        @before_hook = before_hook
        @after_hook = after_hook
      end

      def execute(tool_calls, history)
        sequential = tool_calls.any? { |tc| tool_sequential?(tc) }

        if sequential
          execute_sequential(tool_calls, history)
        else
          execute_parallel(tool_calls, history)
        end
      end

      private

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

      def execute_sequential(tool_calls, history)
        tool_calls.map { |tc| execute_single(tc, history) }
      end

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

        result = @tool_registry.execute(tc.name, tc.arguments)
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

      def tool_sequential?(tc)
        tool = @tool_registry.lookup(tc.name)
        return false unless tool
        tool.const_defined?(:EXECUTION_MODE) && tool::EXECUTION_MODE == :sequential
      end
    end
  end
end
