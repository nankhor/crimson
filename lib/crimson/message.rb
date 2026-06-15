# frozen_string_literal: true

require 'json'

module Crimson
  # Namespace for message types used in conversation history.
  module Message
    # Base class for all message types.
    # @abstract
    class Base
      # @return [String] the role name (e.g. "system", "user", "assistant", "tool")
      attr_reader :role

      # @param role [String]
      def initialize(role)
        @role = role
      end
    end

    # A system-level message carrying instructions or context.
    class System < Base
      # @return [String] the system message content
      attr_reader :content

      # @param content [String]
      def initialize(content)
        super("system")
        @content = content
      end

      # @return [Hash] OpenAI-compatible representation
      def to_openai_h
        { role: "system", content: @content }
      end

      # @return [Hash] Anthropic-compatible representation
      def to_anthropic_h
        { type: "text", text: @content }
      end
    end

    # A user message.
    class User < Base
      # @return [String] the user message content
      attr_reader :content

      # @param content [String]
      def initialize(content)
        super("user")
        @content = content
      end

      # @return [Hash] OpenAI-compatible representation
      def to_openai_h
        { role: "user", content: @content }
      end

      # @return [Hash] Anthropic-compatible representation
      def to_anthropic_h
        { role: "user", content: @content }
      end
    end

    # An assistant (model) response, optionally containing tool calls.
    class Assistant < Base
      # @return [String, nil] the text content
      # @return [Array<ToolCall>] any tool calls requested
      attr_reader :content, :tool_calls

      # @param content [String, nil]
      # @param tool_calls [Array<ToolCall>]
      def initialize(content: nil, tool_calls: [])
        super("assistant")
        @content = content
        @tool_calls = tool_calls
      end

      # @return [Boolean] whether this message contains tool calls
      def tool_call?
        !@tool_calls.nil? && !@tool_calls.empty?
      end

      # @return [Hash] OpenAI-compatible representation
      def to_openai_h
        h = { role: "assistant" }
        h[:content] = @content if @content
        h[:tool_calls] = @tool_calls.map(&:to_openai_h) if tool_call?
        h
      end

      # @return [Hash] Anthropic-compatible representation
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

    # Represents a tool/function call requested by the model.
    class ToolCall
      # @return [String] unique identifier for this tool call
      # @return [String] name of the tool
      # @return [Hash] arguments passed to the tool
      attr_reader :id, :name, :arguments

      # @param id [String]
      # @param name [String]
      # @param arguments [Hash]
      def initialize(id:, name:, arguments: {})
        @id = id
        @name = name
        @arguments = arguments
      end

      # @return [Hash] OpenAI-compatible tool call representation
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

    # The result of executing a tool call, sent back to the model.
    class ToolResult < Base
      # @return [String] the ID of the tool call this result belongs to
      # @return [String] the tool name
      # @return [String] the result content
      attr_reader :tool_call_id, :name, :content

      # @param tool_call_id [String]
      # @param name [String]
      # @param content [String]
      def initialize(tool_call_id:, name:, content:)
        super("tool")
        @tool_call_id = tool_call_id
        @name = name
        @content = content
      end

      # @return [Hash] OpenAI-compatible representation
      def to_openai_h
        {
          role: "tool",
          tool_call_id: @tool_call_id,
          content: @content
        }
      end

      # @return [Hash] Anthropic-compatible representation
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
