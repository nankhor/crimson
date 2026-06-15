# frozen_string_literal: true

require "securerandom"
require "json"

module Crimson
  # Data model for a single entry in a session log.
  # Can represent user messages, assistant responses, and tool results.
  class SessionEntry
    # @return [String] unique entry ID
    # @return [String, nil] parent entry ID for threading
    # @return [String] role (user/assistant/tool_result/system)
    # @return [String, nil] message content
    # @return [Array<Hash>] tool call data
    # @return [String, nil] tool call ID for results
    # @return [String, nil] tool name for results
    # @return [Hash] token usage metadata
    # @return [String] ISO 8601 timestamp
    # @return [Array<String>] files read by this entry
    # @return [Array<String>] files modified by this entry
    attr_accessor :id, :parent_id, :role, :content,
                  :tool_calls, :tool_call_id, :tool_name,
                  :token_usage, :timestamp,
                  :read_files, :modified_files

    # @param attrs [Hash] entry attributes
    def initialize(attrs = {})
      @id = attrs[:id] || SecureRandom.uuid
      @parent_id = attrs[:parent_id]
      @role = attrs[:role]
      @content = attrs[:content]
      @tool_calls = attrs[:tool_calls] || []
      @tool_call_id = attrs[:tool_call_id]
      @tool_name = attrs[:tool_name]
      @token_usage = attrs[:token_usage] || {}
      @timestamp = attrs[:timestamp] || Time.now.utc.iso8601
      @read_files = attrs[:read_files] || []
      @modified_files = attrs[:modified_files] || []
    end

    # Convert to a hash suitable for JSON serialization.
    # @return [Hash]
    def to_h
      h = {
        id: @id,
        parentId: @parent_id,
        role: @role,
        content: @content,
        toolCalls: @tool_calls,
        timestamp: @timestamp
      }
      h[:toolCallId] = @tool_call_id if @tool_call_id
      h[:toolName] = @tool_name if @tool_name
      h[:tokenUsage] = @token_usage unless @token_usage.empty?
      h[:readFiles] = @read_files unless @read_files.empty?
      h[:modifiedFiles] = @modified_files unless @modified_files.empty?
      h
    end

    # @return [String] JSON representation
    def to_json(*_args)
      JSON.generate(to_h)
    end

    # Deserialize from a hash (with string or symbol keys).
    # @param hash [Hash]
    # @return [SessionEntry]
    def self.from_h(hash)
      new(
        id: hash[:id] || hash["id"],
        parent_id: hash[:parentId] || hash["parentId"],
        role: hash[:role] || hash["role"],
        content: hash[:content] || hash["content"],
        tool_calls: hash[:toolCalls] || hash["toolCalls"] || [],
        tool_call_id: hash[:toolCallId] || hash["toolCallId"],
        tool_name: hash[:toolName] || hash["toolName"],
        token_usage: hash[:tokenUsage] || hash["tokenUsage"] || {},
        timestamp: hash[:timestamp] || hash["timestamp"],
        read_files: hash[:readFiles] || hash["readFiles"] || [],
        modified_files: hash[:modifiedFiles] || hash["modifiedFiles"] || []
      )
    end

    # Build a session entry from a message object.
    # @param message [Message::Base]
    # @param parent_id [String, nil]
    # @param read_files [Array<String>]
    # @param modified_files [Array<String>]
    # @return [SessionEntry]
    def self.from_message(message, parent_id:, read_files: [], modified_files: [])
      case message
      when Message::User
        new(role: "user", content: message.content, parent_id: parent_id)
      when Message::Assistant
        tc_data = message.tool_calls.map do |tc|
          { "id" => tc.id, "name" => tc.name, "arguments" => tc.arguments }
        end
        new(
          role: "assistant",
          content: message.content,
          parent_id: parent_id,
          tool_calls: tc_data
        )
      when Message::ToolResult
        new(
          role: "tool_result",
          content: message.content,
          parent_id: parent_id,
          tool_call_id: message.tool_call_id,
          tool_name: message.name,
          read_files: read_files,
          modified_files: modified_files
        )
      else
        new(role: "system", content: message&.content.to_s, parent_id: parent_id)
      end
    end

    # Convert back to a Message object.
    # @return [Message::Base, nil]
    def to_message
      case @role
      when "user"
        Message::User.new(@content)
      when "assistant"
        tcs = (@tool_calls || []).map do |tc|
          Message::ToolCall.new(
            id: tc["id"],
            name: tc["name"],
            arguments: tc["arguments"]
          )
        end
        Message::Assistant.new(content: @content, tool_calls: tcs)
      when "tool_result"
        Message::ToolResult.new(
          tool_call_id: @tool_call_id,
          name: @tool_name,
          content: @content
        )
      else
        nil
      end
    end
  end
end
