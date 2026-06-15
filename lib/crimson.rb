# frozen_string_literal: true

require_relative "crimson/version"
require_relative "crimson/config"
require_relative "crimson/providers"
require_relative "crimson/message"
require_relative "crimson/tools/index"
require_relative "crimson/tool_registry"
require_relative "crimson/skill_router"
require_relative "crimson/formatter"
require_relative "crimson/client/base"
require_relative "crimson/client/factory"
require_relative "crimson/agent/event_emitter"
require_relative "crimson/agent/events"
require_relative "crimson/agent/steering"
require_relative "crimson/agent/tool_executor"
require_relative "crimson/agent"
require_relative "crimson/output_handler"
require_relative "crimson/repl"
require_relative "crimson/setup"
require_relative "crimson/project_context"
require_relative "crimson/session_entry"
require_relative "crimson/session_manager"
require_relative "crimson/cost_tracker"
require_relative "crimson/compactor"
require_relative "crimson/retry_handler"
require_relative "crimson/token_counter"
require_relative "crimson/trust_manager"

module Crimson
  # Base error class for Crimson-specific errors.
  class Error < StandardError; end

  # Directory for Crimson configuration files.
  CONFIG_DIR = File.join(Dir.home, ".crimson")
  # Path to the JSON configuration file.
  CONFIG_FILE = File.join(CONFIG_DIR, "config.json")
  # Directory for user skill markdown files.
  SKILLS_DIR = File.join(CONFIG_DIR, "skills")

  # @return [Config] the global configuration (loaded once, cached)
  def self.config
    @config ||= Crimson::Config.load
  end

  # @return [String] path to the config directory
  def self.config_dir
    CONFIG_DIR
  end

  # @return [Boolean] whether the config file exists
  def self.configured?
    File.exist?(CONFIG_FILE)
  end
end
