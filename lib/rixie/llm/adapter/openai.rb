# frozen_string_literal: true

begin
  require "openai"
rescue LoadError
  raise Rixie::ConfigurationError, "ruby-openai gem is required. Add `gem 'ruby-openai'` to your Gemfile."
end

module Rixie
  module LLM
    module Adapter
      class OpenAI
        def initialize(model:, base_url:, api_key:, request_timeout: nil)
          @model = model
          params = {access_token: api_key, uri_base: base_url}
          params[:request_timeout] = request_timeout if request_timeout
          @client = ::OpenAI::Client.new(**params)
        end

        def chat(messages, tools:)
          params = {model: @model, messages: messages}
          params[:tools] = tools unless tools.empty?

          raw = @client.chat(parameters: params)
          Rixie::LLM::Response.new(raw: raw, provider: :openai)
        end
      end
    end
  end
end
