require 'tty-prompt'
require 'tty-spinner'
require 'net/http'
require 'uri'
require 'json'
require 'fileutils'
require_relative 'providers'

module Crimson
  class Setup
    def self.first_run
      copy_default_skills
      run
    end

    def self.run
      prompt = TTY::Prompt.new
      puts "Crimson Setup"
      puts "============="
      puts

      provider = select_provider(prompt)
      api_key = ask_for_api_key(prompt, provider)
      base_url = ask_for_base_url(prompt) if provider == :custom
      models = fetch_models(provider, api_key, base_url)

      if models.empty?
        puts "No models found for the provided API key."
        return
      end

      model = select_model(prompt, models)
      save_config(provider, api_key, base_url, model)

      puts
      puts "Configuration saved to #{Crimson::CONFIG_FILE}"
    end

    private

    def self.select_provider(prompt)
      prompt.select("Select a provider:",
        PROVIDERS.map { |key, data| { name: data[:name], value: key } }
      )
    end

    def self.ask_for_api_key(prompt, provider)
      prompt.mask("Enter your #{PROVIDERS[provider][:name]} API key:")
    end

    def self.ask_for_base_url(prompt)
      prompt.ask("Enter the base URL for the provider:")
    end

    def self.select_model(prompt, models)
      prompt.select("Select a model:", models)
    end

    def self.fetch_models(provider, api_key, base_url = nil)
      spinner = TTY::Spinner.new("[:spinner] Fetching models...", format: :dots)
      spinner.auto_spin

      url_str = base_url || PROVIDERS[provider][:base_url]
      url_str += MODELS_ENDPOINT
      uri = URI(url_str)

      headers = PROVIDERS[provider][:auth_headers].call(api_key)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Get.new(uri.request_uri, headers)

      begin
        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          spinner.error("Failed!")
          return []
        end

        data = JSON.parse(response.body)
        models = data["data"].map { |model| model["id"] }

        spinner.success("Done!")
        models
      rescue => e
        spinner.error("Error: #{e.message}")
        []
      end
    end

    def self.save_config(provider, api_key, base_url, model)
      config = Crimson::Config.new(
        provider: provider.to_s,
        model: model,
        api_key: api_key,
        base_url: base_url,
        max_tokens: 1000
      )
      config.save
    end

    def self.copy_default_skills
      FileUtils.mkdir_p(Crimson::SKILLS_DIR)

      gem_root = File.expand_path("../..", __dir__)
      bundled_skills_dir = File.join(gem_root, "skills")

      return unless Dir.exist?(bundled_skills_dir)

      Dir.glob(File.join(bundled_skills_dir, "*.md")).each do |file|
        dest = File.join(Crimson::SKILLS_DIR, File.basename(file))
        FileUtils.cp(file, dest) unless File.exist?(dest)
      end
    end
  end
end
