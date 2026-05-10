# frozen_string_literal: true

require_relative "client/resolver"

module Rixie
  module LLM
    class Client
      def initialize(model: nil, provider: nil, adapter: nil)
        @adapter = adapter || Client::Resolver.resolve(model: model, provider: provider)
      end

      def chat(messages, tools:)
        @adapter.chat(messages, tools: tools)
      end
    end
  end
end
