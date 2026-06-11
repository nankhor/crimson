require 'json'
require 'anthropic'
require_relative 'base'

module Crimson
  module Client
    class AnthropicAdapter < Base
      def initialize(config)
        super
        @client = Anthropic::Client.new(api_key: config.api_key)
      end

      def chat(messages:, tools: [], &stream_callback)
        system_msg, chat_msgs = split_messages(messages)

        params = {
          model: @config.model,
          max_tokens: @config.max_tokens
        }
        params[:system] = system_msg if system_msg
        params[:messages] = chat_msgs
        params[:tools] = tools unless tools.empty?

        if block_given?
          stream_chat(params, &stream_callback)
        else
          non_stream_chat(params)
        end
      end

      private

      def split_messages(messages)
        system_parts = []
        chat_msgs = []

        messages.each do |msg|
          case msg
          when Message::System
            system_parts << msg.content
          when Message::ToolResult
            anthropic_h = msg.to_anthropic_h
            last_msg = chat_msgs.last
            if last_msg && last_msg[:role] == "user" && last_msg[:content].is_a?(Array)
              last_msg[:content].concat(anthropic_h[:content])
            else
              chat_msgs << anthropic_h
            end
          else
            chat_msgs << msg.to_anthropic_h
          end
        end

        system_text = system_parts.join("\n\n")
        system_text = nil if system_text.empty?

        [system_text, chat_msgs]
      end

      def stream_chat(params, &callback)
        collected_content = String.new
        collected_tool_calls = {}
        current_tool_use = nil
        collected_usage = nil

        stream = @client.messages.stream(
          model: params[:model],
          max_tokens: params[:max_tokens],
          system: params[:system],
          messages: params[:messages],
          tools: params[:tools]
        )

        stream.each do |event|
          case event.type
          when "message_delta"
            if event.respond_to?(:usage)
              u = event.usage
              collected_usage = {
                prompt_tokens: u&.input_tokens || 0,
                completion_tokens: u&.output_tokens || 0,
                total_tokens: (u&.input_tokens || 0) + (u&.output_tokens || 0)
              }
            end
          when "content_block_delta"
            delta = event.delta
            next unless delta

            delta_type = delta[:type] || delta["type"]
            if delta_type == "text_delta"
              text = delta[:text] || delta["text"] || ""
              collected_content << text
              callback.call(text, nil)
            elsif delta_type == "input_json_delta"
              partial = delta[:partial_json] || delta["partial_json"] || ""
              current_tool_use[:arguments] << partial if current_tool_use
            end
          when "content_block_start"
            content_block = event.content_block
            next unless content_block

            cb_type = content_block[:type] || content_block["type"]
            if cb_type == "tool_use"
              current_tool_use = {
                id: content_block[:id] || content_block["id"],
                name: content_block[:name] || content_block["name"],
                arguments: String.new
              }
            end
          when "content_block_stop"
            if current_tool_use
              callback.call(nil, current_tool_use)
              collected_tool_calls[current_tool_use[:id]] = current_tool_use
              current_tool_use = nil
            end
          end
        end

        [build_assistant_message(collected_content, collected_tool_calls.values), collected_usage]
      rescue => e
        [Message::Assistant.new(content: "Error communicating with Anthropic: #{e.message}"), nil]
      end

      def non_stream_chat(params)
        response = @client.messages.create(
          model: params[:model],
          max_tokens: params[:max_tokens],
          system: params[:system],
          messages: params[:messages],
          tools: params[:tools]
        )

        content = String.new
        tool_calls = []

        Array(response.content).each do |block|
          block_type = block[:type] || block["type"]
          if block_type == "text"
            content << (block[:text] || block["text"] || "")
          elsif block_type == "tool_use"
            tool_calls << Message::ToolCall.new(
              id: block[:id] || block["id"],
              name: block[:name] || block["name"],
              arguments: block[:input] || block["input"] || {}
            )
          end
        end

        usage = response.usage
        usage_h = usage ? {
          prompt_tokens: usage.input_tokens || 0,
          completion_tokens: usage.output_tokens || 0,
          total_tokens: (usage.input_tokens || 0) + (usage.output_tokens || 0)
        } : nil

        [Message::Assistant.new(content: content.empty? ? nil : content.to_s, tool_calls: tool_calls), usage_h]
      rescue => e
        [Message::Assistant.new(content: "Error communicating with Anthropic: #{e.message}"), nil]
      end

      def build_assistant_message(content, tool_calls)
        tc = tool_calls.map do |raw|
          args = begin
            JSON.parse(raw[:arguments], symbolize_names: false)
          rescue JSON::ParserError
            {}
          end
          Message::ToolCall.new(id: raw[:id], name: raw[:name], arguments: args)
        end

        Message::Assistant.new(
          content: content.empty? ? nil : content.to_s,
          tool_calls: tc
        )
      end
    end
  end
end
