# frozen_string_literal: true

require_relative "client/resolver"

module Rixie
  module LLM
    class Client
      attr_reader :model, :provider

      def initialize(model: nil, provider: nil, adapter: nil, stream: false, request_timeout: nil, max_tokens: nil, temperature: nil, parallel_tool_calls: nil)
        @model = model
        @provider = provider
        @stream = stream
        @adapter = adapter || Client::Resolver.resolve(
          model: model,
          provider: provider,
          request_timeout: request_timeout,
          max_tokens: max_tokens,
          temperature: temperature,
          parallel_tool_calls: parallel_tool_calls
        )
      end

      def call(messages, tools:, &block)
        if @stream
          @adapter.stream(messages, tools: tools, &block)
        else
          @adapter.chat(messages, tools: tools)
        end
      end
    end
  end
end
