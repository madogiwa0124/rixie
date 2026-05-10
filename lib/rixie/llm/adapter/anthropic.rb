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
        DEFAULT_MAX_TOKENS = 4096

        def initialize(model:, base_url:, api_key:, request_timeout: nil, max_tokens: nil, temperature: nil)
          @model = model
          @max_tokens = max_tokens || DEFAULT_MAX_TOKENS
          @temperature = temperature
          @client = ::Anthropic::Client.new(access_token: api_key)
        end

        def chat(messages, tools:)
          params = {model: @model, messages: messages, max_tokens: @max_tokens}
          params[:tools] = tools unless tools.empty?
          params[:temperature] = @temperature unless @temperature.nil?

          result = @client.messages(parameters: params)
          Rixie::LLM::Response.new(raw: normalize(result))
        rescue ::Anthropic::Errors::Error => e
          raise Rixie::LLM::Error, e.message
        end

        private

        def normalize(result)
          blocks = result["content"] || []
          tool_calls = blocks.select { |b| b["type"] == "tool_use" }.map do |tc|
            {"id" => tc["id"], "function" => {"name" => tc["name"], "arguments" => JSON.generate(tc["input"] || {})}}
          end
          text_blocks = blocks.select { |b| b["type"] == "text" }.map { |b| b["text"] }
          content = text_blocks.empty? ? nil : text_blocks.join

          {
            "choices" => [{
              "message" => {
                "content" => content,
                "tool_calls" => tool_calls.empty? ? nil : tool_calls
              }
            }]
          }
        end
      end
    end
  end
end
