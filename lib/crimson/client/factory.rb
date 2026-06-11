require_relative 'base'
require_relative 'openai_adapter'
require_relative 'anthropic_adapter'

module Crimson
  module Client
    def self.create(config)
      provider = config.provider.to_sym
      sdk = PROVIDERS[provider][:sdk]

      case sdk
      when :openai
        OpenAIAdapter.new(config)
      when :anthropic
        AnthropicAdapter.new(config)
      else
        raise Error, "Unsupported provider: #{config.provider}"
      end
    end
  end
end
