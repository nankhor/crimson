module Crimson
  module RetryHandler
    MAX_RETRIES = 3
    BASE_DELAY = 1.0
    MAX_DELAY = 30.0

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

          delay = [base_delay * (2 ** (attempts - 1)), max_delay].min
          delay += rand * 0.5

          sleep delay
        end
      end
    end

    def self.retryable?(error)
      message = "#{error.class}: #{error.message}"
      RETRYABLE_MESSAGES.any? { |pattern| message.match?(pattern) }
    end
  end
end
