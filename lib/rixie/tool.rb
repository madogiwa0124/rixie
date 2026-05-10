# frozen_string_literal: true

module Rixie
  class Tool
    attr_reader :name, :description, :input_schema

    def initialize(name:, description:, input_schema:, call:)
      @name = name
      @description = description
      @input_schema = input_schema
      @call = call
    end

    def call(arguments)
      @call.call(arguments)
    end

    def to_definition
      {
        type: "function",
        function: {
          name: @name,
          description: @description,
          parameters: @input_schema
        }
      }
    end
  end
end
