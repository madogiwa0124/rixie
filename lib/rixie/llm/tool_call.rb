# frozen_string_literal: true

require "json"

module Rixie
  module LLM
    class ToolCall
      attr_reader :id, :name, :arguments

      def initialize(id:, name:, arguments:)
        @id = id
        @name = name
        @arguments = arguments
      end

      def self.from_openai_wire(raw)
        name = raw["function"]["name"]
        arguments = begin
          JSON.parse(raw["function"]["arguments"])
        rescue JSON::ParserError => e
          raise Rixie::LLM::Error, "Invalid JSON in arguments for tool call #{name.inspect}: #{e.message}"
        end
        new(id: raw["id"], name: name, arguments: arguments)
      end

      def to_openai_wire
        {
          "id" => @id,
          "type" => "function",
          "function" => {
            "name" => @name,
            "arguments" => JSON.generate(@arguments)
          }
        }
      end
    end
  end
end
