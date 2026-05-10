# frozen_string_literal: true

begin
  require "anthropic"
rescue LoadError
  raise Rixie::ConfigurationError, "anthropic gem is required. Add `gem 'anthropic'` to your Gemfile."
end

module Rixie
  module LLM
    module Adapter
      class Anthropic
        def initialize(model:, base_url:, api_key:, request_timeout: nil)
          @model = model
          @client = ::Anthropic::Client.new(access_token: api_key)
        end

        def chat(messages, tools:)
          params = {model: @model, messages: messages, max_tokens: 4096}
          params[:tools] = tools unless tools.empty?

          raw = @client.messages(parameters: params)
          Rixie::LLM::Response.new(raw: raw, provider: :anthropic)
        end
      end
    end
  end
end
