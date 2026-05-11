# frozen_string_literal: true

# Minimal stub of the openai gem for testing purposes.
module OpenAI
  module Errors
    class Error < StandardError; end
  end

  class Client
    def initialize(api_key:, base_url:, timeout: nil)
      @api_key = api_key
      @base_url = base_url
    end

    def chat
      Chat.new
    end

    class Chat
      def completions
        Completions.new
      end

      class Completions
        def create(**)
          nil
        end

        def stream_raw(**)
          []
        end
      end
    end
  end
end
