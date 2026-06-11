module Crimson
  class Agent
    module Events
      AGENT_START = :agent_start
      TURN_START = :turn_start
      MESSAGE_START = :message_start
      MESSAGE_UPDATE = :message_update
      MESSAGE_END = :message_end
      TOOL_EXECUTION_START = :tool_execution_start
      TOOL_EXECUTION_UPDATE = :tool_execution_update
      TOOL_EXECUTION_END = :tool_execution_end
      TURN_END = :turn_end
      AGENT_END = :agent_end

      ALL = [
        AGENT_START,
        TURN_START,
        MESSAGE_START,
        MESSAGE_UPDATE,
        MESSAGE_END,
        TOOL_EXECUTION_START,
        TOOL_EXECUTION_UPDATE,
        TOOL_EXECUTION_END,
        TURN_END,
        AGENT_END
      ].freeze
    end
  end
end
