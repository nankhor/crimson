module Crimson
  PROVIDERS = {
    openai: {
      name: "OpenAI",
      base_url: "https://api.openai.com/v1",
      sdk: :openai,
      auth_headers: ->(key) { { "Authorization" => "Bearer #{key}" } }
    },
    anthropic: {
      name: "Anthropic",
      base_url: "https://api.anthropic.com/v1",
      sdk: :anthropic,
      auth_headers: ->(key) { { "x-api-key" => key, "anthropic-version" => "2023-06-01" } }
    },
    openrouter: {
      name: "OpenRouter",
      base_url: "https://openrouter.ai/api/v1",
      sdk: :openai,
      auth_headers: ->(key) { { "Authorization" => "Bearer #{key}" } }
    },
    mistral: {
      name: "Mistral",
      base_url: "https://api.mistral.ai/v1",
      sdk: :openai,
      auth_headers: ->(key) { { "Authorization" => "Bearer #{key}" } }
    },
    xai: {
      name: "xAI (Grok)",
      base_url: "https://api.x.ai/v1",
      sdk: :openai,
      auth_headers: ->(key) { { "Authorization" => "Bearer #{key}" } }
    },
    custom: {
      name: "Custom (OpenAI-compatible)",
      base_url: nil,
      sdk: :openai,
      auth_headers: ->(key) { { "Authorization" => "Bearer #{key}" } }
    }
  }

  MODELS_ENDPOINT = "/models"
end
