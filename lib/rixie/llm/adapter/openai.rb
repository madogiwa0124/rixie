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
        def initialize(model:, base_url:, api_key:, request_timeout: nil, max_tokens: nil, temperature: nil)
          @model = model
          @max_tokens = max_tokens
          @temperature = temperature
          params = {api_key: api_key, base_url: base_url}
          params[:timeout] = request_timeout if request_timeout
          @client = ::OpenAI::Client.new(**params)
        end

        def chat(messages, tools:)
          result = @client.chat.completions.create(**build_params(messages, tools))
          Rixie::LLM::Response.new(raw: normalize(result))
        rescue ::OpenAI::Errors::Error => e
          raise Rixie::LLM::Error, e.message
        end

        def stream(messages, tools:, &block)
          params = build_params(messages, tools)

          content = +""
          accumulated_tool_calls = {}

          @client.chat.completions.stream_raw(**params).each do |chunk|
            delta = chunk.choices&.first&.delta
            next unless delta

            if (text = delta.content) && !text.empty?
              block.call(Event::Token.new(delta: text))
              content << text
            end

            delta.tool_calls&.each do |tc|
              i = tc.index
              accumulated_tool_calls[i] ||= {
                "id" => +"",
                "function" => {"name" => +"", "arguments" => +""}
              }
              accumulated_tool_calls[i]["id"] << tc.id.to_s
              accumulated_tool_calls[i]["function"]["name"] << tc.function&.name.to_s
              accumulated_tool_calls[i]["function"]["arguments"] << tc.function&.arguments.to_s
            end
          end

          build_stream_response(content, accumulated_tool_calls)
        rescue ::OpenAI::Errors::Error => e
          raise Rixie::LLM::Error, e.message
        end

        private

        def build_stream_response(content, accumulated_tool_calls)
          tool_calls = accumulated_tool_calls.empty? ? nil : accumulated_tool_calls.values
          raw = {
            "choices" => [{
              "message" => {
                "content" => content.empty? ? nil : content,
                "tool_calls" => tool_calls
              }
            }]
          }
          Rixie::LLM::Response.new(raw: raw)
        end

        def build_params(messages, tools)
          params = {model: @model, messages: messages}
          params[:tools] = tools unless tools.empty?
          params[:max_tokens] = @max_tokens if @max_tokens
          params[:temperature] = @temperature unless @temperature.nil?
          params
        end

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
