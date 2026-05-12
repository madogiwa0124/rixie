# frozen_string_literal: true

module Rixie
  module LLM
    module Adapter
      class Dummy
        DEFAULT_RESPONSE = {
          "choices" => [{
            "finish_reason" => "stop",
            "message" => {"role" => "assistant", "content" => "[mock llm generated content]"}
          }]
        }.freeze

        def initialize(responses = nil, **_)
          @responses = responses.is_a?(Array) ? responses.dup : nil
        end

        def chat(messages, tools:)
          if @responses.nil?
            return Rixie::LLM::Response.from_openai_wire(DEFAULT_RESPONSE)
          end

          raise "Rixie::LLM::Adapter::Dummy exhausted: no more responses enqueued" if @responses.empty?

          Rixie::LLM::Response.from_openai_wire(@responses.shift)
        end

        def stream(messages, tools:, &block)
          response = chat(messages, tools: tools)
          if (content = response.content)
            block.call(Rixie::Event::Token.new(delta: content))
          end
          response
        end

      end
    end
  end
end
