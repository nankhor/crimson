# frozen_string_literal: true

module Crimson
  class Agent
    # Event type constants for the agent pub/sub system.
    module Events
      # Emitted when the agent begins processing a user request.
      AGENT_START = :agent_start
      # Emitted at the start of each agent turn.
      TURN_START = :turn_start
      # Emitted when a new message is created.
      MESSAGE_START = :message_start
      # Emitted with streaming text deltas during message generation.
      MESSAGE_UPDATE = :message_update
      # Emitted when a message is fully received.
      MESSAGE_END = :message_end
      # Emitted when a tool begins executing.
      TOOL_EXECUTION_START = :tool_execution_start
      # Emitted with partial results during tool execution (e.g. command output).
      TOOL_EXECUTION_UPDATE = :tool_execution_update
      # Emitted when a tool finishes execution.
      TOOL_EXECUTION_END = :tool_execution_end
      # Emitted at the end of each agent turn.
      TURN_END = :turn_end
      # Emitted when the agent finishes processing.
      AGENT_END = :agent_end

      # All known event types.
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
