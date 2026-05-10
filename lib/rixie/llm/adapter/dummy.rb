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

        def initialize(responses = nil)
          @responses = responses&.dup
        end

        def chat(messages, tools:)
          if @responses.nil?
            return Rixie::LLM::Response.new(raw: DEFAULT_RESPONSE)
          end

          raise "Rixie::LLM::Adapter::Dummy exhausted: no more responses enqueued" if @responses.empty?

          Rixie::LLM::Response.new(raw: @responses.shift)
        end
      end
    end
  end
end
