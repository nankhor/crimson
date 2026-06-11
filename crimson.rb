require_relative 'src/version'
require_relative 'src/config'
require_relative 'src/providers'
require_relative 'src/message'
require_relative 'src/tools'
require_relative 'src/tool_registry'
require_relative 'src/client/base'
require_relative 'src/client/openai_adapter'
require_relative 'src/client/anthropic_adapter'
require_relative 'src/client/factory'
require_relative 'src/agent'
require_relative 'src/repl'
require_relative 'src/setup'
require_relative 'src/project_context'

module Crimson
  class Error < StandardError; end

  def self.config
    @config ||= Crimson::Config.load
  end
end
