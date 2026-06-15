# frozen_string_literal: true

require 'json'

module Crimson
  # Configuration model with JSON file persistence.
  # Stores provider, model, API key, and other connection settings.
  class Config
    # @return [String, nil] provider name
    # @return [String, nil] model identifier
    # @return [String, nil] API key
    # @return [String, nil] custom base URL
    # @return [Integer] max tokens for responses
    # @return [String, nil] thinking level (off/low/medium/high)
    attr_reader :provider, :model, :api_key, :base_url, :max_tokens, :thinking_level

    # Valid thinking level values.
    VALID_THINKING_LEVELS = %w[off low medium high].freeze

    # @param provider [String, nil]
    # @param model [String, nil]
    # @param api_key [String, nil]
    # @param base_url [String, nil]
    # @param max_tokens [Integer]
    # @param thinking_level [String, nil]
    def initialize(provider: nil, model: nil, api_key: nil, base_url: nil, max_tokens: 8192, thinking_level: nil)
      @provider = provider
      @model = model
      @api_key = api_key
      @base_url = base_url
      @max_tokens = max_tokens
      @thinking_level = validate_thinking_level(thinking_level)
    end

    # Load configuration from the JSON config file.
    # @return [Config]
    def self.load
      return new unless File.exist?(Crimson::CONFIG_FILE)

      data = JSON.parse(File.read(Crimson::CONFIG_FILE))
      new(
        provider: data["provider"],
        model: data["model"],
        api_key: data["api_key"],
        base_url: data["base_url"],
        max_tokens: data["max_tokens"] || 1000,
        thinking_level: data["thinking_level"]
      )
    rescue JSON::ParserError => e
      raise Error, "Invalid config file: #{e.message}"
    end

    # Persist configuration to the JSON config file with restricted permissions.
    # @return [void]
    def save
      FileUtils.mkdir_p(File.dirname(Crimson::CONFIG_FILE))

      data = {
        provider: @provider,
        model: @model,
        api_key: @api_key,
        base_url: @base_url,
        max_tokens: @max_tokens,
        thinking_level: @thinking_level
      }

      File.write(Crimson::CONFIG_FILE, JSON.pretty_generate(data))
      File.chmod(0o600, Crimson::CONFIG_FILE)
    end

    # @return [Boolean] whether required fields are present
    def valid?
      return false if @provider.nil? || @provider.empty?
      return false if @model.nil? || @model.empty?
      return false if @api_key.nil? || @api_key.empty?
      return false if @provider == "custom" && (@base_url.nil? || @base_url.empty?)
      true
    end

    # @param level [String, nil]
    def thinking_level=(level)
      @thinking_level = validate_thinking_level(level)
    end

    private

    # @param level [String, nil]
    # @return [String, nil]
    def validate_thinking_level(level)
      return nil if level.nil?
      level = level.to_s.downcase
      VALID_THINKING_LEVELS.include?(level) ? level : nil
    end
  end
end
