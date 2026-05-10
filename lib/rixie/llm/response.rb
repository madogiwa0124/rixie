# frozen_string_literal: true

require "json"

module Rixie
  module LLM
    class Response
      def initialize(raw:, provider:)
        @raw = raw
        @provider = provider
      end

      def has_tool_calls?
        tool_calls.any?
      end

      def tool_calls
        @tool_calls ||= extract_tool_calls
      end

      def content
        @content ||= extract_content
      end

      private

      def extract_tool_calls
        case @provider
        when :anthropic
          anthropic_tool_calls
        else
          openai_tool_calls
        end
      end

      def extract_content
        case @provider
        when :anthropic
          anthropic_content
        else
          openai_content
        end
      end

      def openai_tool_calls
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

      def openai_content
        @raw.dig("choices", 0, "message", "content")
      end

      def anthropic_tool_calls
        blocks = @raw["content"] || []
        blocks.select { |b| b["type"] == "tool_use" }.map do |tc|
          {
            "id" => tc["id"],
            "function" => {
              "name" => tc["name"],
              "arguments" => JSON.generate(tc["input"] || {})
            }
          }
        end
      end

      def anthropic_content
        blocks = @raw["content"] || []
        text_blocks = blocks.select { |b| b["type"] == "text" }.map { |b| b["text"] }
        text_blocks.empty? ? nil : text_blocks.join
      end
    end
  end
end
