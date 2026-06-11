require_relative "crimson/version"
require_relative "crimson/config"
require_relative "crimson/providers"
require_relative "crimson/message"
require_relative "crimson/tools"
require_relative "crimson/tool_registry"
require_relative "crimson/formatter"
require_relative "crimson/client/base"
require_relative "crimson/client/factory"
require_relative "crimson/agent/event_emitter"
require_relative "crimson/agent/events"
require_relative "crimson/agent/steering"
require_relative "crimson/agent/tool_executor"
require_relative "crimson/agent"
require_relative "crimson/repl"
require_relative "crimson/setup"
require_relative "crimson/project_context"
require_relative "crimson/session_entry"
require_relative "crimson/session_manager"
require_relative "crimson/cost_tracker"
require_relative "crimson/compactor"

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
