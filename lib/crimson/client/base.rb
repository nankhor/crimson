module Crimson
  module Client
    class Base
      def initialize(config)
        @config = config
      end

      def chat(messages:, tools: [], &stream_callback)
        raise NotImplementedError, "#{self.class}#chat must be implemented"
      end
    end
  end
end
