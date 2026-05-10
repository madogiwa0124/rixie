# frozen_string_literal: true

begin
  require "openai"
rescue LoadError
  raise Rixie::ConfigurationError, "openai gem is required. Add `gem 'openai'` to your Gemfile."
end

module Rixie
  module LLM
    module Adapter
      class OpenAI
        def initialize(model:, base_url:, api_key:, request_timeout: nil)
          @model = model
          params = {api_key: api_key, base_url: base_url}
          params[:timeout] = request_timeout if request_timeout
          @client = ::OpenAI::Client.new(**params)
        end

        def chat(messages, tools:)
          params = {model: @model, messages: messages}
          params[:tools] = tools unless tools.empty?

          result = @client.chat.completions.create(**params)
          Rixie::LLM::Response.new(raw: normalize(result))
        rescue ::OpenAI::Errors::Error => e
          raise Rixie::LLM::Error, e.message
        end

        private

        def normalize(result)
          {
            "choices" => (result.choices || []).map do |choice|
              message = choice.message
              {
                "message" => {
                  "content" => message.content,
                  "tool_calls" => message.tool_calls&.map do |tc|
                    {
                      "id" => tc.id,
                      "function" => {"name" => tc.function.name, "arguments" => tc.function.arguments}
                    }
                  end
                }
              }
            end
          }
        end
      end
    end
  end
end
