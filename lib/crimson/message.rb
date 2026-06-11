require 'json'

module Crimson
  module Message
    class Base
      attr_reader :role

      def initialize(role)
        @role = role
      end
    end

    class System < Base
      attr_reader :content

      def initialize(content)
        super("system")
        @content = content
      end

      def to_openai_h
        { role: "system", content: @content }
      end

      def to_anthropic_h
        { type: "text", text: @content }
      end
    end

    class User < Base
      attr_reader :content

      def initialize(content)
        super("user")
        @content = content
      end

      def to_openai_h
        { role: "user", content: @content }
      end

      def to_anthropic_h
        { role: "user", content: @content }
      end
    end

    class Assistant < Base
      attr_reader :content, :tool_calls

      def initialize(content: nil, tool_calls: [])
        super("assistant")
        @content = content
        @tool_calls = tool_calls
      end

      def tool_call?
        !@tool_calls.nil? && !@tool_calls.empty?
      end

      def to_openai_h
        h = { role: "assistant" }
        h[:content] = @content if @content
        h[:tool_calls] = @tool_calls.map(&:to_openai_h) if tool_call?
        h
      end

      def to_anthropic_h
        content_blocks = []
        content_blocks << { type: "text", text: @content } if @content && !@content.empty?
        @tool_calls.each do |tc|
          content_blocks << {
            type: "tool_use",
            id: tc.id,
            name: tc.name,
            input: tc.arguments
          }
        end
        { role: "assistant", content: content_blocks }
      end
    end

    class ToolCall
      attr_reader :id, :name, :arguments

      def initialize(id:, name:, arguments: {})
        @id = id
        @name = name
        @arguments = arguments
      end

      def to_openai_h
        {
          id: @id,
          type: "function",
          function: {
            name: @name,
            arguments: JSON.generate(@arguments)
          }
        }
      end
    end

    class ToolResult < Base
      attr_reader :tool_call_id, :name, :content

      def initialize(tool_call_id:, name:, content:)
        super("tool")
        @tool_call_id = tool_call_id
        @name = name
        @content = content
      end

      def to_openai_h
        {
          role: "tool",
          tool_call_id: @tool_call_id,
          content: @content
        }
      end

      def to_anthropic_h
        {
          role: "user",
          content: [
            {
              type: "tool_result",
              tool_use_id: @tool_call_id,
              content: @content
            }
          ]
        }
      end
    end
  end
end
