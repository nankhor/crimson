module Crimson
  class Agent
    class EventEmitter
      def initialize
        @listeners = Hash.new { |h, k| h[k] = [] }
      end

      def on(event_type, &handler)
        @listeners[event_type] << handler
        handler
      end

      def off(event_type, handler)
        @listeners[event_type].delete(handler)
      end

      def emit(event_type, **payload)
        @listeners[event_type].each do |handler|
          handler.call(event_type, **payload)
        end
      end

      def clear
        @listeners.clear
      end

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
