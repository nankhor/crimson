require_relative 'base'

module Crimson
module Client
  def self.create(config)
    provider = config.provider.to_sym
    sdk = PROVIDERS[provider][:sdk]

    case sdk
    when :openai
      require_relative 'openai_adapter'
      OpenAIAdapter.new(config)
    when :anthropic
      require_relative 'anthropic_adapter'
      AnthropicAdapter.new(config)
    else
      raise Error, "Unsupported provider: #{config.provider}"
    end
  end
end
end
