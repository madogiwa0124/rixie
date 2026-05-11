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
          result = @client.messages(parameters: build_params(messages, tools))
          Rixie::LLM::Response.new(raw: normalize(result))
        rescue ::Anthropic::Errors::Error => e
          raise Rixie::LLM::Error, e.message
        end

        def stream(messages, tools:, &block)
          params = build_params(messages, tools)

          content = +""
          accumulated_tool_calls = {}
          current_tool_index = nil

          @client.messages(parameters: params) do |event|
            case event.type
            when "content_block_start"
              if event.content_block.type == "tool_use"
                current_tool_index = accumulated_tool_calls.size
                accumulated_tool_calls[current_tool_index] = {
                  "id"       => event.content_block.id,
                  "function" => {"name" => event.content_block.name, "arguments" => +""}
                }
              end
            when "content_block_delta"
              if event.delta.type == "text_delta"
                block.call(Event::Token.new(delta: event.delta.text))
                content << event.delta.text
              elsif event.delta.type == "input_json_delta"
                accumulated_tool_calls[current_tool_index]["function"]["arguments"] <<
                  event.delta.partial_json
              end
            end
          end

          build_stream_response(content, accumulated_tool_calls)
        rescue ::Anthropic::Errors::Error => e
          raise Rixie::LLM::Error, e.message
        end

        private

        def build_stream_response(content, accumulated_tool_calls)
          tool_calls = accumulated_tool_calls.empty? ? nil : accumulated_tool_calls.values
          raw = {
            "choices" => [{
              "message" => {
                "content"    => content.empty? ? nil : content,
                "tool_calls" => tool_calls
              }
            }]
          }
          Rixie::LLM::Response.new(raw: raw)
        end

        def build_params(messages, tools)
          params = {model: @model, messages: messages, max_tokens: @max_tokens}
          params[:tools] = tools unless tools.empty?
          params[:temperature] = @temperature unless @temperature.nil?
          params
        end

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
