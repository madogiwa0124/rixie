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
        def initialize(model:, base_url:, api_key:, request_timeout: nil, temperature: nil, parallel_tool_calls: true, provider_params: nil)
          @model = model
          @temperature = temperature
          @parallel_tool_calls = parallel_tool_calls
          @provider_params = provider_params || {}
          params = {api_key: api_key, base_url: base_url}
          params[:timeout] = request_timeout if request_timeout
          @client = ::OpenAI::Client.new(**params)
        end

        def chat(messages, tools:, schema: nil)
          result = @client.chat.completions.create(**build_params(encode_messages(messages), tools, schema))
          Rixie::LLM::Response.from_openai_wire(normalize(result))
        rescue ::OpenAI::Errors::Error => e
          raise Rixie::LLM::Error, e.message
        end

        def stream(messages, tools:, schema: nil, &block)
          params = build_params(encode_messages(messages), tools, schema)

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
            {role: "user", content: encode_user_content(msg.content)}
          when Rixie::Message::Assistant
            h = {role: "assistant", content: msg.content}
            h[:tool_calls] = msg.tool_calls.map(&:to_openai_wire) unless msg.tool_calls.empty?
            h
          when Rixie::Message::Tool
            {role: "tool", tool_call_id: msg.tool_call_id, content: msg.content}
          end
        end

        # A user message's content is either a plain String (unchanged behavior)
        # or an Array of Rixie unified content blocks, which are translated here to
        # OpenAI's wire format. Keys may be symbols (caller-supplied) or strings
        # (round-tripped through JSON-backed session stores), so both are accepted.
        def encode_user_content(content)
          return content unless content.is_a?(Array)

          content.map { |block| encode_content_block(block) }
        end

        def encode_content_block(block)
          unless block.is_a?(Hash)
            raise Rixie::InvalidContentError, "Invalid content block: expected a Hash, got #{block.inspect}."
          end

          case fetch_key(block, :type).to_s
          when "text"
            {type: "text", text: fetch_key(block, :text)}
          when "image"
            {type: "image_url", image_url: {url: encode_image_data_uri(fetch_key(block, :source))}}
          else
            raise Rixie::InvalidContentError,
              "Unknown content block type: #{fetch_key(block, :type).inspect}. Expected \"text\" or \"image\"."
          end
        end

        # Only base64 image sources are supported. Reject anything else (missing
        # fields, or the out-of-scope `source.type: "url"` form) with a clear
        # error instead of emitting a malformed `data:;base64,` URI.
        def encode_image_data_uri(source)
          source = {} if source.nil?
          unless source.is_a?(Hash)
            raise Rixie::InvalidContentError, "Invalid image source: expected a Hash, got #{source.inspect}."
          end

          media_type = fetch_key(source, :media_type).to_s
          data = fetch_key(source, :data).to_s
          unless fetch_key(source, :type).to_s == "base64" && !media_type.empty? && !data.empty?
            raise Rixie::InvalidContentError,
              "Invalid image content block: expected source { type: \"base64\", media_type:, data: }, got #{source.inspect}."
          end

          "data:#{media_type};base64,#{data}"
        end

        def fetch_key(hash, key)
          hash[key] || hash[key.to_s]
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

        def build_params(messages, tools, schema = nil)
          params = {model: @model, messages: messages}
          unless tools.empty?
            params[:tools] = encode_tools(tools)
            params[:parallel_tool_calls] = @parallel_tool_calls
          end
          params[:response_format] = encode_response_format(schema) if schema
          params[:temperature] = @temperature unless @temperature.nil?
          params.merge!(@provider_params)
          params
        end

        # OpenAI native structured output. `strict: false` keeps arbitrary
        # caller-supplied JSON Schemas usable without forcing OpenAI's strict-mode
        # constraints (every property required, additionalProperties: false).
        def encode_response_format(schema)
          {
            type: "json_schema",
            json_schema: {name: "structured_output", schema: schema, strict: false}
          }
        end

        def normalize(result)
          usage_raw = result.respond_to?(:usage) && result.usage
          usage_hash = usage_raw ? {"prompt_tokens" => usage_raw.prompt_tokens, "completion_tokens" => usage_raw.completion_tokens} : nil
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
            end,
            "usage" => usage_hash
          }
        end
      end
    end
  end
end
