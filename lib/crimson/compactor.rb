module Crimson
  class Compactor
    APPROX_CHARS_PER_TOKEN = 4
    DEFAULT_MAX_CONTEXT_TOKENS = 100_000
    KEEP_RECENT_MESSAGES = 4

    def initialize(client:, max_context_tokens: DEFAULT_MAX_CONTEXT_TOKENS)
      @client = client
      @max_context_tokens = max_context_tokens
    end

    def needs_compaction?(history)
      estimated_tokens(history) > @max_context_tokens * 0.8
    end

    def compact(history, system_prompt:)
      return history if history.length <= KEEP_RECENT_MESSAGES + 1

      older = history[0...-KEEP_RECENT_MESSAGES]
      recent = history[-KEEP_RECENT_MESSAGES..]

      summary = summarize(older, system_prompt)

      compacted = []
      compacted << Message::User.new("[Previous conversation summary]\n#{summary}")
      compacted << Message::Assistant.new("Understood. I have the context from the previous conversation.")
      compacted.concat(recent)
      compacted
    end

    private

    def summarize(messages, system_prompt)
      summary_prompt = "Summarize the following conversation between a user and an AI coding assistant. " \
        "Preserve all important details: file paths discussed, code changes made, errors encountered, " \
        "decisions reached, and any unresolved issues. Be concise but complete.\n\n" \
        "Conversation:\n#{format_messages(messages)}"

      msgs = [
        Message::System.new("You are a helpful assistant that summarizes conversations concisely."),
        Message::User.new(summary_prompt)
      ]

      response, _usage = @client.chat(messages: msgs, tools: [])
      response&.content || "Summary unavailable"
    end

    def format_messages(messages)
      messages.map do |msg|
        case msg
        when Message::User
          "User: #{msg.content}"
        when Message::Assistant
          tool_str = msg.tool_calls.any? ? " [called: #{msg.tool_calls.map(&:name).join(", ")}]" : ""
          "Assistant: #{msg.content}#{tool_str}"
        when Message::ToolResult
          "Tool (#{msg.name}): #{truncate(msg.content.to_s, 200)}"
        else
          nil
        end
      end.compact.join("\n")
    end

    def estimated_tokens(history)
      total_chars = history.sum { |msg| msg.content.to_s.length }
      total_chars / APPROX_CHARS_PER_TOKEN
    end

    def truncate(text, max)
      text.length > max ? "#{text[0...max]}..." : text
    end
  end
end
