require "thread"

module Crimson
  class Agent
    class SteeringManager
      def initialize
        @steering_mutex = Mutex.new
        @steering_queue = []
        @follow_up_queue = []
      end

      def steer(message)
        @steering_mutex.synchronize { @steering_queue << message }
      end

      def follow_up(message)
        @steering_mutex.synchronize { @follow_up_queue << message }
      end

      def has_steering?
        @steering_mutex.synchronize { !@steering_queue.empty? }
      end

      def has_follow_up?
        @steering_mutex.synchronize { !@follow_up_queue.empty? }
      end

      def pop_steering
        @steering_mutex.synchronize { @steering_queue.shift }
      end

      def pop_follow_up
        @steering_mutex.synchronize { @follow_up_queue.shift }
      end

      def pop_all_steering
        @steering_mutex.synchronize do
          msgs = @steering_queue.dup
          @steering_queue.clear
          msgs
        end
      end

      def pop_all_follow_up
        @steering_mutex.synchronize do
          msgs = @follow_up_queue.dup
          @follow_up_queue.clear
          msgs
        end
      end

      def clear_all
        @steering_mutex.synchronize do
          @steering_queue.clear
          @follow_up_queue.clear
        end
      end

      def steering_count
        @steering_mutex.synchronize { @steering_queue.size }
      end

      def follow_up_count
        @steering_mutex.synchronize { @follow_up_queue.size }
      end
    end
  end
end
