# frozen_string_literal: true

module Crimson
  module Tools
    # Per-file mutex queue to serialize write/edit operations on the same path.
    class FileMutationQueue
      def initialize
        @queues = {}
        @global_mutex = Mutex.new
      end

      # Execute a block with exclusive access to the given file.
      # @param path [String] file path
      # @yield block to run under the file's mutex
      # @return [Object] the block's result
      def with_file(path)
        normalized = File.expand_path(path)
        queue = @global_mutex.synchronize do
          @queues[normalized] ||= Mutex.new
        end

        queue.synchronize { yield }
      ensure
        @global_mutex.synchronize do
          @queues.delete(normalized) if queue && !queue.locked?
        end
      end
    end
  end
end
