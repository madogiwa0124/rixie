# frozen_string_literal: true

require "json"

module Rixie
  class Agent
    class ToolCall
      attr_reader :id, :name, :arguments

      def initialize(id:, name:, arguments:)
        @id = id
        @name = name
        @arguments = arguments
      end

      def self.build_from_raw(raw)
        new(
          id: raw["id"],
          name: raw["function"]["name"],
          arguments: JSON.parse(raw["function"]["arguments"])
        )
      end

      def to_llm_format
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
