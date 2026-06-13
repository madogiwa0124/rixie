# frozen_string_literal: true

require "json"

module Rixie
  class Agent
    # Parses and validates the agent's final (`:finish`) answer against a JSON
    # Schema. Pure: it holds no `llm_client` or `listener` and runs no loop. The
    # corrective retry loop lives in `Agent#think`, which re-generates the finish
    # answer and asks this object to `parse` again — so only the finish turn is
    # re-run on failure, never the tool-calling iterations.
    class StructuredOutput
      DEFAULT_MAX_RETRIES = 3

      # The outcome of parsing one candidate answer. `value` is the parsed Hash
      # on success; `error` is a human-readable reason on failure (and is fed
      # back to the model via `correction_message`).
      Result = Data.define(:value, :error) do
        def valid? = error.nil?
      end

      def initialize(schema:)
        @schema = schema
      end

      # Parses `content` as JSON and validates it against the schema.
      def parse(content)
        return Result.new(value: nil, error: "response was empty") if content.nil? || content.to_s.strip.empty?

        parsed = JSON.parse(content)
        error = validate(parsed, @schema, "$")
        Result.new(value: error ? nil : parsed, error: error)
      rescue JSON::ParserError => e
        Result.new(value: nil, error: "response was not valid JSON (#{e.message})")
      end

      # A corrective user message nudging the model back toward the schema.
      def correction_message(content, error)
        Message::User.new(content: <<~MSG)
          Your previous response did not conform to the required JSON schema.
          Error: #{error}

          Respond with ONLY a valid JSON value matching this JSON Schema:
          #{JSON.generate(@schema)}

          Your previous response was:
          #{content}
        MSG
      end

      private

      # Minimal recursive JSON Schema validation: `type`, `required`, `properties`,
      # and array `items`. Sufficient to accept or reject a finish response and
      # drive the corrective retry — not a general-purpose validator.
      def validate(value, schema, path)
        type = schema["type"] || schema[:type]
        return type_error(type, value, path) unless type_matches?(type, value)

        case type
        when "object" then validate_object(value, schema, path)
        when "array" then validate_array(value, schema, path)
        end
      end

      def validate_object(value, schema, path)
        required = schema["required"] || schema[:required] || []
        missing = required.map(&:to_s) - value.keys.map(&:to_s)
        return "#{path}: missing required #{missing.map(&:inspect).join(", ")}" unless missing.empty?

        properties = schema["properties"] || schema[:properties] || {}
        properties.each do |key, prop_schema|
          key = key.to_s
          next unless value.key?(key)

          error = validate(value[key], prop_schema, "#{path}.#{key}")
          return error if error
        end
        nil
      end

      def validate_array(value, schema, path)
        items = schema["items"] || schema[:items]
        return nil if items.nil?

        value.each_with_index do |item, i|
          error = validate(item, items, "#{path}[#{i}]")
          return error if error
        end
        nil
      end

      def type_matches?(type, value)
        case type
        when nil then true
        when "object" then value.is_a?(Hash)
        when "array" then value.is_a?(Array)
        when "string" then value.is_a?(String)
        when "integer" then value.is_a?(Integer)
        when "number" then value.is_a?(Numeric)
        when "boolean" then value == true || value == false
        when "null" then value.nil?
        else true
        end
      end

      def type_error(type, value, path)
        "#{path}: expected #{type}, got #{value.class}"
      end
    end
  end
end
