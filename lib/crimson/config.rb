require 'json'

module Crimson
  class Config
    attr_reader :provider, :model, :api_key, :base_url, :max_tokens

    def initialize(provider: nil, model: nil, api_key: nil, base_url: nil, max_tokens: 1000)
      @provider = provider
      @model = model
      @api_key = api_key
      @base_url = base_url
      @max_tokens = max_tokens
    end

    def self.load
      return new unless File.exist?(Crimson::CONFIG_FILE)

      data = JSON.parse(File.read(Crimson::CONFIG_FILE))
      new(
        provider: data["provider"],
        model: data["model"],
        api_key: data["api_key"],
        base_url: data["base_url"],
        max_tokens: data["max_tokens"] || 1000
      )
    rescue JSON::ParserError => e
      raise Error, "Invalid config file: #{e.message}"
    end

    def save
      FileUtils.mkdir_p(File.dirname(Crimson::CONFIG_FILE))

      data = {
        provider: @provider,
        model: @model,
        api_key: @api_key,
        base_url: @base_url,
        max_tokens: @max_tokens
      }

      File.write(Crimson::CONFIG_FILE, JSON.pretty_generate(data))
    end

    def valid?
      return false if @provider.nil? || @provider.empty?
      return false if @model.nil? || @model.empty?
      return false if @api_key.nil? || @api_key.empty?
      return false if @provider == "custom" && (@base_url.nil? || @base_url.empty?)
      true
    end
  end
end
