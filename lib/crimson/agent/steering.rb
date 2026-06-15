# frozen_string_literal: true

require "thread"

module Crimson
  class Agent
    # Thread-safe queue for steering messages and follow-ups injected into agent turns.
    class SteeringManager
      def initialize
        @steering_mutex = Mutex.new
        @steering_queue = []
        @follow_up_queue = []
      end

      # Enqueue a steering message.
      # @param message [Message::User]
      # @return [void]
      def steer(message)
        @steering_mutex.synchronize { @steering_queue << message }
      end

      # Enqueue a follow-up message.
      # @param message [Message::User]
      # @return [void]
      def follow_up(message)
        @steering_mutex.synchronize { @follow_up_queue << message }
      end

      # @return [Boolean] whether steering messages are queued
      def has_steering?
        @steering_mutex.synchronize { !@steering_queue.empty? }
      end

      # @return [Boolean] whether follow-up messages are queued
      def has_follow_up?
        @steering_mutex.synchronize { !@follow_up_queue.empty? }
      end

      # Dequeue a single steering message.
      # @return [Message::User, nil]
      def pop_steering
        @steering_mutex.synchronize { @steering_queue.shift }
      end

      # Dequeue a single follow-up message.
      # @return [Message::User, nil]
      def pop_follow_up
        @steering_mutex.synchronize { @follow_up_queue.shift }
      end

      # Dequeue all steering messages.
      # @return [Array<Message::User>]
      def pop_all_steering
        @steering_mutex.synchronize do
          msgs = @steering_queue.dup
          @steering_queue.clear
          msgs
        end
      end

      # Dequeue all follow-up messages.
      # @return [Array<Message::User>]
      def pop_all_follow_up
        @steering_mutex.synchronize do
          msgs = @follow_up_queue.dup
          @follow_up_queue.clear
          msgs
        end
      end

      # Clear all queued messages.
      # @return [void]
      def clear_all
        @steering_mutex.synchronize do
          @steering_queue.clear
          @follow_up_queue.clear
        end
      end

      # @return [Integer] number of queued steering messages
      def steering_count
        @steering_mutex.synchronize { @steering_queue.size }
      end

      # @return [Integer] number of queued follow-up messages
      def follow_up_count
        @steering_mutex.synchronize { @follow_up_queue.size }
      end
    end
  end
end
