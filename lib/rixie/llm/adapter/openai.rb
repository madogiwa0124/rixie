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
        def initialize(model:, base_url:, api_key:, request_timeout: nil, max_tokens: nil, temperature: nil, parallel_tool_calls: true)
          @model = model
          @max_tokens = max_tokens
          @temperature = temperature
          @parallel_tool_calls = parallel_tool_calls
          params = {api_key: api_key, base_url: base_url}
          params[:timeout] = request_timeout if request_timeout
          @client = ::OpenAI::Client.new(**params)
        end

        def chat(messages, tools:)
          result = @client.chat.completions.create(**build_params(encode_messages(messages), tools))
          Rixie::LLM::Response.from_openai_wire(normalize(result))
        rescue ::OpenAI::Errors::Error => e
          raise Rixie::LLM::Error, e.message
        end

        def stream(messages, tools:, &block)
          params = build_params(encode_messages(messages), tools)

          content = +""
          accumulated_tool_calls = {}
          finish_reason = nil

          @client.chat.completions.stream_raw(**params).each do |chunk|
            choice = chunk.choices&.first
            next unless choice

            finish_reason = choice.finish_reason if choice.finish_reason
            delta = choice.delta
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

          Rixie::LLM::Response.from_openai_wire(build_stream_raw(content, accumulated_tool_calls, finish_reason))
        rescue ::OpenAI::Errors::Error => e
          raise Rixie::LLM::Error, e.message
        end

        private

        def encode_messages(messages)
          messages.map { |msg| encode_message(msg) }
        end

        def encode_message(msg)
          case msg
          when Rixie::Message::System
            {role: "system", content: msg.content}
          when Rixie::Message::User
            {role: "user", content: msg.content}
          when Rixie::Message::Assistant
            h = {role: "assistant", content: msg.content}
            h[:tool_calls] = msg.tool_calls.map(&:to_openai_wire) unless msg.tool_calls.empty?
            h
          when Rixie::Message::Tool
            {role: "tool", tool_call_id: msg.tool_call_id, content: msg.content}
          end
        end

        def build_stream_raw(content, accumulated_tool_calls, finish_reason)
          tool_calls_raw = accumulated_tool_calls.empty? ? nil : accumulated_tool_calls.values
          {
            "choices" => [{
              "finish_reason" => finish_reason,
              "message" => {
                "content" => content.empty? ? nil : content,
                "tool_calls" => tool_calls_raw
              }
            }]
          }
        end

        def encode_tools(tools)
          tools.map do |tool|
            {
              type: "function",
              function: {
                name: tool.name,
                description: tool.description,
                parameters: tool.input_schema
              }
            }
          end
        end

        def build_params(messages, tools)
          params = {model: @model, messages: messages}
          unless tools.empty?
            params[:tools] = encode_tools(tools)
            params[:parallel_tool_calls] = @parallel_tool_calls
          end
          params[:max_tokens] = @max_tokens if @max_tokens
          params[:temperature] = @temperature unless @temperature.nil?
          params
        end

        def normalize(result)
          {
            "choices" => (result.choices || []).map do |choice|
              message = choice.message
              {
                "finish_reason" => choice.finish_reason,
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
