# frozen_string_literal: true

# Minimal stub of the anthropic gem for testing purposes.
module Anthropic
  module Errors
    class Error < StandardError; end
  end

  class Client
    def initialize(access_token:)
      @access_token = access_token
    end

    def messages(parameters:, &block)
      {}
    end
  end
end
