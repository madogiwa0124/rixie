# frozen_string_literal: true

module Rixie
  class Tool
    attr_reader :name, :description, :input_schema

    def initialize(name:, description:, input_schema:, call:, return_direct: false)
      @name = name
      @description = description
      @input_schema = input_schema
      @call = call
      @return_direct = return_direct
    end

    def return_direct?
      @return_direct
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
