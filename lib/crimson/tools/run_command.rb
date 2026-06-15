# frozen_string_literal: true

require "open3"
require "timeout"

module Crimson
  module Tools
    # Execute shell commands with timeout, streaming output, and abort support.
    module RunCommand
      TOOL_NAME = "run_command"
      # This tool must run sequentially (not parallel).
      EXECUTION_MODE = :sequential

      # Tool parameter definitions.
      PARAMS = {
        command: { type: "string", description: "The shell command to execute" },
        timeout: { type: "integer", description: "Timeout in seconds (default: 30)" }
      }.freeze

      @update_callback = nil
      @callback_mutex = Mutex.new

      class << self
        # Register a callback for streaming execution updates.
        # @param callback [Proc, nil]
        def on_update=(callback)
          @callback_mutex.synchronize { @update_callback = callback }
        end

        # @return [Proc, nil] current update callback
        def on_update
          @callback_mutex.synchronize { @update_callback }
        end
      end

      # @return [Hash] OpenAI-compatible tool definition
      def self.definition
        Schema.build(name: TOOL_NAME, description: "Execute a shell command and return stdout and stderr.", parameters: PARAMS, required: ["command"])
      end

      # @return [Hash] Anthropic-compatible tool definition
      def self.anthropic_definition
        Schema.build_anthropic(name: TOOL_NAME, description: "Execute a shell command and return stdout and stderr.", parameters: PARAMS, required: ["command"])
      end

      # Execute a command without abort signal support.
      # @param command [String] shell command
      # @param timeout [Integer] timeout in seconds
      # @return [String] command output or error
      def self.call(command:, timeout: 30)
        call_with_signal(command: command, timeout: timeout, signal: nil)
      end

      # Execute a command with abort signal support.
      # @param command [String] shell command
      # @param timeout [Integer] timeout in seconds
      # @param signal [AbortSignal, nil]
      # @return [String] command output or error
      def self.call_with_signal(command:, timeout: 30, signal: nil)
        return "Error: No command provided" if command.nil? || command.strip.empty?

        stdout = String.new
        stderr = String.new
        status = nil
        start_time = Time.now

        begin
          Timeout.timeout(timeout) do
            Open3.popen3(command) do |stdin, out, err, wait_thr|
              stdin.close

              abort_thread = if signal
                Thread.new do
                  sleep 0.1 until signal.aborted? || !wait_thr.status
                  if signal.aborted? && wait_thr.pid
                    begin
                      Process.kill("TERM", wait_thr.pid)
                    rescue Errno::ESRCH, Errno::EPERM
                    end
                  end
                end
              end

              readers = [out, err]
              while readers.any?
                ready = IO.select(readers, nil, nil, 0.1)
                next unless ready

                ready[0].each do |io|
                  chunk = io.read_nonblock(4096, exception: false)
                  if chunk == :wait_readable || chunk.nil?
                    readers.delete(io) if io.eof?
                    next
                  end
                  if io == out
                    stdout << chunk
                  else
                    stderr << chunk
                  end
                  elapsed = Time.now - start_time
                  cb = on_update
                  cb&.call(command, elapsed, stdout.length + stderr.length)
                end
              end

              status = wait_thr.value
              abort_thread&.kill
            end
          end

          output = String.new
          output << stdout if !stdout.empty?
          output << stderr if !stderr.empty?

          output = strip_ansi_codes(output)
          output = String.new("(no output)") if output.strip.empty?
          if status.success?
            # No exit code line needed for success
          elsif status.exitstatus
            output << "\n(exit code: #{status.exitstatus})"
          else
            output << "\n(process killed)"
          end
          output
        rescue Timeout::Error
          "Error: Command timed out after #{timeout} seconds"
        rescue => e
          "Error executing command: #{e.message}"
        end
      end

      # @api private
      def self.strip_ansi_codes(text)
        text.gsub(/\e\[[0-9;]*[a-zA-Z]/, '')
      end
    end
  end
end
