# frozen_string_literal: true

require "strscan"

module Rixie
  class Tool
    # Recursive-descent parser for arithmetic expressions.
    # Supports: + - * / % ^ ** (), unary minus/plus, ints / floats / scientific notation.
    class CalculatorParser
      class Error < StandardError; end

      ADDITIVE = ["+", "-"].freeze
      MULTIPLICATIVE = ["*", "/", "%"].freeze
      POWER = ["**", "^"].freeze

      def self.evaluate(expression)
        new(expression).parse
      end

      def initialize(expression)
        @tokens = tokenize(expression)
        @pos = 0
      end

      def parse
        result = expression
        raise Error, "Unexpected token: #{peek.inspect}" if peek
        result
      end

      private

      def tokenize(input)
        scanner = StringScanner.new(input.to_s)
        tokens = []
        until scanner.eos?
          scanner.skip(/\s+/)
          break if scanner.eos?

          if (num = scanner.scan(/\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/))
            tokens << (num.match?(/[.eE]/) ? num.to_f : num.to_i)
          elsif (op = scanner.scan(/\*\*|[+\-*\/%^()]/))
            tokens << op
          else
            raise Error, "Invalid character at position #{scanner.pos}: #{scanner.peek(1).inspect}"
          end
        end
        tokens
      end

      def peek = @tokens[@pos]

      def consume
        token = @tokens[@pos]
        @pos += 1
        token
      end

      def expression
        left = term
        while ADDITIVE.include?(peek)
          op = consume
          right = term
          left = (op == "+") ? left + right : left - right
        end
        left
      end

      def term
        left = power
        while MULTIPLICATIVE.include?(peek)
          op = consume
          right = power
          left = apply_multiplicative(op, left, right)
        end
        left
      end

      def apply_multiplicative(op, left, right)
        case op
        when "*" then left * right
        when "/"
          raise Error, "Division by zero" if right.zero?
          # Promote integer division to float to avoid surprising truncation.
          (left.is_a?(Integer) && right.is_a?(Integer)) ? left.fdiv(right) : left / right
        when "%"
          raise Error, "Modulo by zero" if right.zero?
          left % right
        end
      end

      def power
        left = unary
        if POWER.include?(peek)
          consume
          right = power # right-associative
          left **= right
        end
        left
      end

      def unary
        case peek
        when "-" then consume
                      -unary
        when "+" then consume
                      unary
        else primary
        end
      end

      def primary
        token = consume
        return parse_parenthesized if token == "("
        return token if token.is_a?(Numeric)

        raise Error, "Unexpected token: #{token.inspect}"
      end

      def parse_parenthesized
        value = expression
        raise Error, "Expected ')'" unless consume == ")"
        value
      end
    end
    private_constant :CalculatorParser

    Calculator = Tool.new(
      name: "calculator",
      description: "Evaluate an arithmetic expression and return the result. " \
                   "Supports + - * / % and ^ (or **) for exponentiation, plus parentheses. " \
                   "Use this for any non-trivial arithmetic — LLMs are unreliable at calculation.",
      input_schema: {
        type: "object",
        properties: {
          expression: {
            type: "string",
            description: "An arithmetic expression, e.g. '(2 + 3) * 4 ^ 2'"
          }
        },
        required: ["expression"]
      },
      call: ->(args) {
        begin
          expr = args["expression"] || args[:expression]
          result = CalculatorParser.evaluate(expr)
          result.to_s
        rescue CalculatorParser::Error => e
          "Error: #{e.message}"
        end
      }
    )
  end
end
