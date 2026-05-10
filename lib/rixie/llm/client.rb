# frozen_string_literal: true

require_relative "client/resolver"

module Rixie
  module LLM
    class Client
      def initialize(model: nil, provider: nil, adapter: nil, request_timeout: nil, max_tokens: nil, temperature: nil)
        @adapter = adapter || Client::Resolver.resolve(
          model: model,
          provider: provider,
          request_timeout: request_timeout,
          max_tokens: max_tokens,
          temperature: temperature
        )
      end

      def chat(messages, tools:)
        @adapter.chat(messages, tools: tools)
      end
    end
  end
end
