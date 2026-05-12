# frozen_string_literal: true

module Rixie
  module LLM
    Response = Data.define(:content, :tool_calls, :finish_reason) do
      def self.from_openai_wire(raw)
        choices = raw["choices"] || []
        choice = choices.first || {}
        message = choice["message"] || {}
        tool_calls = (message["tool_calls"] || []).map { |tc| LLM::ToolCall.from_openai_wire(tc) }
        new(content: message["content"], tool_calls: tool_calls, finish_reason: choice["finish_reason"])
      end

      def has_tool_calls?
        tool_calls.any?
      end
    end
  end
end
