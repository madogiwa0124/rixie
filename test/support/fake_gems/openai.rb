# frozen_string_literal: true

# Minimal stub of the ruby-openai gem for testing purposes.
module OpenAI
  class Client
    def initialize(access_token:, uri_base:)
      @access_token = access_token
      @uri_base = uri_base
    end

    def chat(parameters:)
      {}
    end
  end
end
