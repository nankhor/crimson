# frozen_string_literal: true

module Crimson
  module Tools
    # Helper for building OpenAI and Anthropic tool definition schemas.
    module Schema
      # Build an OpenAI-compatible tool definition.
      # @param name [String]
      # @param description [String]
      # @param parameters [Hash] JSON Schema properties
      # @param required [Array<String>]
      # @return [Hash]
      def self.build(name:, description:, parameters:, required:)
        {
          type: "function",
          function: {
            name: name,
            description: description,
            parameters: {
              type: "object",
              properties: parameters,
              required: required
            }
          }
        }
      end

      # Build an Anthropic-compatible tool definition.
      # @param name [String]
      # @param description [String]
      # @param parameters [Hash] JSON Schema properties
      # @param required [Array<String>]
      # @return [Hash]
      def self.build_anthropic(name:, description:, parameters:, required:)
        {
          name: name,
          description: description,
          input_schema: {
            type: "object",
            properties: parameters,
            required: required
          }
        }
      end

      # Build both OpenAI and Anthropic definitions at once.
      # @param name [String]
      # @param description [String]
      # @param parameters [Hash]
      # @param required [Array<String>]
      # @return [Hash] with keys :openai and :anthropic
      def self.definitions_for(name:, description:, parameters:, required:)
        {
          openai: build(name: name, description: description, parameters: parameters, required: required),
          anthropic: build_anthropic(name: name, description: description, parameters: parameters, required: required)
        }
      end
    end
  end
end
