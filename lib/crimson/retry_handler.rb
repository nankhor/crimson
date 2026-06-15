# frozen_string_literal: true

module Crimson
  # Retry logic for API calls with exponential backoff and retry-After header support.
  module RetryHandler
    # Maximum number of retry attempts.
    MAX_RETRIES = 3
    # Base delay in seconds for exponential backoff.
    BASE_DELAY = 1.0
    # Maximum delay cap in seconds.
    MAX_DELAY = 30.0

    # Patterns in error messages that indicate a retry is appropriate.
    RETRYABLE_MESSAGES = [
      /rate.?limit/i,
      /too many requests/i,
      /429/,
      /5\d{2}/,
      /timeout/i,
      /timed?\s*out/i,
      /connection.*reset/i,
      /connection.*refused/i,
      /ECONNRESET/,
      /ECONNREFUSED/,
      /ETIMEDOUT/,
      /ENOTFOUND/,
      /network/i,
      /overloaded/i,
      /capacity/i,
      /server error/i,
      /service unavailable/i,
      /bad gateway/i,
      /gateway timeout/i,
      /internal server error/i
    ].freeze

    # Execute a block with retry logic.
    # @param max_retries [Integer] maximum retry attempts
    # @param base_delay [Float] base delay in seconds
    # @param max_delay [Float] maximum delay cap
    # @yield block to execute and potentially retry
    # @return [Object] the result of the block
    # @raise [StandardError] if all retries are exhausted or error is non-retryable
    def self.with_retry(max_retries: MAX_RETRIES, base_delay: BASE_DELAY, max_delay: MAX_DELAY)
      attempts = 0
      last_error = nil

      loop do
        attempts += 1
        begin
          return yield
        rescue => e
          last_error = e
          raise e if attempts > max_retries
          raise e unless retryable?(e)

          delay = compute_delay(e, attempts, base_delay, max_delay)
          sleep delay
        end
      end
    end

    # Check whether an error is retryable based on its message.
    # @param error [StandardError]
    # @return [Boolean]
    def self.retryable?(error)
      message = "#{error.class}: #{error.message}"
      RETRYABLE_MESSAGES.any? { |pattern| message.match?(pattern) }
    end

    # Compute delay using exponential backoff, respecting Retry-After headers.
    # @param error [StandardError]
    # @param attempt [Integer] current attempt number
    # @param base_delay [Float]
    # @param max_delay [Float]
    # @return [Float] delay in seconds
    def self.compute_delay(error, attempt, base_delay, max_delay)
      retry_after = extract_retry_after(error)
      return [retry_after, max_delay].min if retry_after && retry_after > 0

      delay = [base_delay * (2 ** (attempt - 1)), max_delay].min
      delay + rand * 0.5
    end

    # Extract Retry-After header from an error response.
    # @api private
    def self.extract_retry_after(error)
      return nil unless error.respond_to?(:response)

      response = error.response
      return nil unless response.is_a?(Hash)

      headers = response[:headers] || response["headers"]
      return nil unless headers.is_a?(Hash)

      retry_after = headers["Retry-After"] || headers["retry-after"]
      return nil unless retry_after

      retry_after.to_f
    rescue
      nil
    end
  end
end
