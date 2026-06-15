# frozen_string_literal: true

module Crimson
  module Client
    # Abstract base class for LLM API client adapters.
    # @abstract Subclasses must implement {#chat}.
    class Base
      # @param config [Config]
      def initialize(config)
        @config = config
      end

      # Send a chat request and return the assistant response.
      # @param messages [Array<Message::Base>] conversation messages
      # @param tools [Array<Hash>] tool definitions
      # @yield [text_chunk, tool_event] optional streaming callback
      # @yieldparam text_chunk [String, nil] incremental text delta
      # @yieldparam tool_event [Hash, nil] partial tool call data
      # @return [Array(Message::Assistant, Hash, nil)] response message and usage data
      def chat(messages:, tools: [], &stream_callback)
        raise NotImplementedError, "#{self.class}#chat must be implemented"
      end
    end
  end
end
