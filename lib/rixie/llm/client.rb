# frozen_string_literal: true

require_relative "client/resolver"

module Rixie
  module LLM
    class Client
      attr_reader :model, :provider

      def initialize(model: nil, provider: nil, adapter: nil, stream: false, request_timeout: nil, temperature: nil, parallel_tool_calls: nil, provider_params: nil)
        @model = model
        @provider = provider
        @stream = stream
        @adapter = adapter || Client::Resolver.resolve(
          model: model,
          provider: provider,
          request_timeout: request_timeout,
          temperature: temperature,
          parallel_tool_calls: parallel_tool_calls,
          provider_params: provider_params
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
