require 'json'
require 'openai'
require_relative 'base'

module Crimson
  module Client
    class OpenAIAdapter < Base
      def initialize(config)
        super
        @client = build_client
      end

      def chat(messages:, tools: [], &stream_callback)
        params = {
          messages: messages.map(&:to_openai_h),
          model: @config.model
        }
        params[:tools] = tools unless tools.empty?

        if block_given?
          stream_chat(params, &stream_callback)
        else
          non_stream_chat(params)
        end
      end

      private

      def build_client
        opts = { api_key: @config.api_key }

        base_url = @config.base_url || PROVIDERS[@config.provider.to_sym][:base_url]
        opts[:base_url] = base_url if base_url

        OpenAI::Client.new(**opts)
      end

      def stream_chat(params, &callback)
        collected_content = String.new
        collected_tool_calls = {}
        usage = nil

        stream = @client.chat.completions.stream(
          messages: params[:messages],
          model: params[:model],
          tools: params[:tools] || []
        )

        stream.each do |event|
          case event
          when OpenAI::Helpers::Streaming::ChatContentDeltaEvent
            text = event.delta
            if text && !text.empty?
              collected_content << text
              callback.call(text, nil)
            end

          when OpenAI::Helpers::Streaming::ChatFunctionToolCallArgumentsDeltaEvent
            idx = event.index
            collected_tool_calls[idx] ||= {
              id: nil,
              name: event.name || "",
              arguments: String.new,
              _emitted: false
            }
            collected_tool_calls[idx][:name] = event.name if event.name
            collected_tool_calls[idx][:arguments] << event.arguments_delta if event.arguments_delta

            # Emit tool call as soon as we have the name
            if event.name && !collected_tool_calls[idx][:_emitted]
              collected_tool_calls[idx][:_emitted] = true
              callback.call(nil, collected_tool_calls[idx])
            end

          when OpenAI::Helpers::Streaming::ChatFunctionToolCallArgumentsDoneEvent
            idx = event.index
            collected_tool_calls[idx] ||= {
              id: nil,
              name: event.name || "",
              arguments: String.new
            }
            collected_tool_calls[idx][:name] = event.name if event.name
            collected_tool_calls[idx][:arguments] = event.arguments if event.arguments

          when OpenAI::Helpers::Streaming::ResponseCompletedEvent
            final = event.response
            if final.respond_to?(:usage) && final.usage
              usage = {
                prompt_tokens: final.usage.prompt_tokens || 0,
                completion_tokens: final.usage.completion_tokens || 0,
                total_tokens: final.usage.total_tokens || 0
              }
            end

          when OpenAI::Helpers::Streaming::ChatChunkEvent
            chunk = event.chunk
            if chunk.respond_to?(:usage) && chunk.usage
              usage = {
                prompt_tokens: chunk.usage.prompt_tokens || 0,
                completion_tokens: chunk.usage.completion_tokens || 0,
                total_tokens: chunk.usage.total_tokens || 0
              }
            end
          end
        end

        # Assign IDs from tool call chunks if we have them
        collected_tool_calls.each do |_idx, tc|
          next if tc[:_emitted]
          callback.call(nil, tc)
        end

        [build_assistant_message(collected_content, collected_tool_calls.values), usage]
      rescue => e
        [Message::Assistant.new(content: "Error communicating with #{provider_name}: #{e.message}"), nil]
      end

      def non_stream_chat(params)
        response = @client.chat.completions.create(
          messages: params[:messages],
          model: params[:model],
          tools: params[:tools] || []
        )

        choice = response.choices&.first
        return [Message::Assistant.new(content: ""), nil] unless choice

        msg = choice.message
        tool_calls = parse_tool_calls(msg.tool_calls) if msg.tool_calls

        usage = response.usage
        usage_h = usage ? {
          prompt_tokens: usage.prompt_tokens || 0,
          completion_tokens: usage.completion_tokens || 0,
          total_tokens: usage.total_tokens || 0
        } : nil

        [Message::Assistant.new(content: msg.content, tool_calls: tool_calls || []), usage_h]
      rescue => e
        [Message::Assistant.new(content: "Error communicating with #{provider_name}: #{e.message}"), nil]
      end

      def parse_tool_calls(raw_tool_calls)
        raw_tool_calls.map do |tc|
          args = begin
            JSON.parse(tc.function.arguments, symbolize_names: false)
          rescue JSON::ParserError
            {}
          end

          Message::ToolCall.new(id: tc.id, name: tc.function.name, arguments: args)
        end
      end

      def build_assistant_message(content, tool_calls)
        tc = tool_calls.map do |raw|
          args = begin
            JSON.parse(raw[:arguments], symbolize_names: false)
          rescue JSON::ParserError
            {}
          end
          Message::ToolCall.new(id: raw[:id] || SecureRandom.uuid, name: raw[:name], arguments: args)
        end

        Message::Assistant.new(
          content: content.empty? ? nil : content.to_s,
          tool_calls: tc
        )
      end

      def provider_name
        PROVIDERS[@config.provider.to_sym][:name]
      end
    end
  end
end
