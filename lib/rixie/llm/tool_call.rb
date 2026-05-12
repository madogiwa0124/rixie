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
        new(
          id: raw["id"],
          name: raw["function"]["name"],
          arguments: JSON.parse(raw["function"]["arguments"])
        )
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
