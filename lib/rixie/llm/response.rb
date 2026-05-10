# frozen_string_literal: true

module Rixie
  module LLM
    class Response
      def initialize(raw:, provider: nil)
        @raw = raw
      end

      def finish_reason
        @raw.dig("choices", 0, "finish_reason")
      end

      def has_tool_calls?
        tool_calls.any?
      end

      def tool_calls
        @tool_calls ||= begin
          message = @raw.dig("choices", 0, "message") || {}
          calls = message["tool_calls"] || []
          calls.map do |tc|
            {
              "id" => tc["id"],
              "function" => {
                "name" => tc.dig("function", "name"),
                "arguments" => tc.dig("function", "arguments")
              }
            }
          end
        end
      end

      def content
        @content ||= @raw.dig("choices", 0, "message", "content")
      end
    end
  end
end
