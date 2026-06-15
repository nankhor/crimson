# frozen_string_literal: true

module Crimson
  class Agent
    # Pub/sub event emitter for agent lifecycle events.
    class EventEmitter
      def initialize
        @listeners = Hash.new { |h, k| h[k] = [] }
      end

      # Register a handler for an event type.
      # @param event_type [Symbol]
      # @yield handler block
      # @return [Proc] the handler
      def on(event_type, &handler)
        @listeners[event_type] << handler
        handler
      end

      # Remove a previously registered handler.
      # @param event_type [Symbol]
      # @param handler [Proc]
      # @return [void]
      def off(event_type, handler)
        @listeners[event_type].delete(handler)
      end

      # Emit an event with keyword payload.
      # @param event_type [Symbol]
      # @param payload [Hash] forwarded as keyword arguments
      # @return [void]
      def emit(event_type, **payload)
        @listeners[event_type].each do |handler|
          handler.call(event_type, **payload)
        end
      end

      # Remove all listeners.
      # @return [void]
      def clear
        @listeners.clear
      end

      # Count listeners, optionally filtered by event type.
      # @param event_type [Symbol, nil]
      # @return [Integer]
      def listener_count(event_type = nil)
        if event_type
          @listeners[event_type].size
        else
          @listeners.values.sum(&:size)
        end
      end
    end
  end
end
