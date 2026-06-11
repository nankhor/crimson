require_relative "crimson/version"
require_relative "crimson/config"
require_relative "crimson/providers"
require_relative "crimson/message"
require_relative "crimson/tools"
require_relative "crimson/tool_registry"
require_relative "crimson/client/base"
require_relative "crimson/client/openai_adapter"
require_relative "crimson/client/anthropic_adapter"
require_relative "crimson/client/factory"
require_relative "crimson/agent"
require_relative "crimson/repl"
require_relative "crimson/setup"
require_relative "crimson/project_context"

module Crimson
  class Error < StandardError; end

  CONFIG_DIR = File.join(Dir.home, ".crimson")
  CONFIG_FILE = File.join(CONFIG_DIR, "config.json")
  SKILLS_DIR = File.join(CONFIG_DIR, "skills")

  def self.config
    @config ||= Crimson::Config.load
  end

  def self.config_dir
    CONFIG_DIR
  end

  def self.configured?
    File.exist?(CONFIG_FILE)
  end
end
