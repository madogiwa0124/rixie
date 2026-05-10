# frozen_string_literal: true

module Rixie
  module LLM
    module Adapter
      class Dummy
        def initialize(responses = [])
          @responses = responses.dup
        end

        def chat(messages, tools:)
          raise "Rixie::LLM::Adapter::Dummy exhausted: no more responses enqueued" if @responses.empty?

          @responses.shift
        end
      end
    end
  end
end
