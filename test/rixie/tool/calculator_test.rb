# frozen_string_literal: true

require "test_helper"

class Rixie::Tool::CalculatorTest < Minitest::Test
  def call(expr)
    Rixie::Tool::Calculator.call({"expression" => expr})
  end

  def test_is_a_tool_instance
    assert_instance_of Rixie::Tool, Rixie::Tool::Calculator
  end

  def test_tool_name_is_calculator
    assert_equal "calculator", Rixie::Tool::Calculator.name
  end

  def test_addition_returns_integer_string
    assert_equal "5", call("2 + 3")
  end

  def test_subtraction
    assert_equal "-1", call("2 - 3")
  end

  def test_multiplication
    assert_equal "12", call("3 * 4")
  end

  def test_division_promotes_to_float
    assert_equal "2.5", call("5 / 2")
  end

  def test_integer_division_for_exact_floats
    assert_equal "2.0", call("4 / 2")
  end

  def test_modulo
    assert_equal "1", call("10 % 3")
  end

  def test_exponent_with_caret
    assert_equal "8", call("2 ^ 3")
  end

  def test_exponent_with_double_star
    assert_equal "8", call("2 ** 3")
  end

  def test_exponent_is_right_associative
    # 2 ^ (3 ^ 2) = 2 ^ 9 = 512, not (2 ^ 3) ^ 2 = 64
    assert_equal "512", call("2 ^ 3 ^ 2")
  end

  def test_parentheses
    assert_equal "20", call("(2 + 3) * 4")
  end

  def test_nested_parentheses
    assert_equal "21", call("((1 + 2) * (3 + 4))")
  end

  def test_unary_minus
    assert_equal "-5", call("-5")
  end

  def test_unary_minus_in_expression
    assert_equal "1", call("-2 + 3")
  end

  def test_unary_minus_before_parenthesis
    assert_equal "-5", call("-(2 + 3)")
  end

  def test_unary_plus
    assert_equal "5", call("+5")
  end

  def test_operator_precedence
    assert_equal "14", call("2 + 3 * 4")
  end

  def test_complex_expression
    assert_equal "50", call("(2 + 3) ^ 2 + 5 * 5")
  end

  def test_float_literal
    assert_equal "3.5", call("1.5 + 2")
  end

  def test_scientific_notation
    assert_equal "1500.0", call("1.5e3")
  end

  def test_whitespace_is_ignored
    assert_equal "6", call("  1  +  2  +  3  ")
  end

  def test_division_by_zero_returns_error
    assert_match(/Division by zero/, call("1 / 0"))
  end

  def test_modulo_by_zero_returns_error
    assert_match(/Modulo by zero/, call("1 % 0"))
  end

  def test_invalid_character_returns_error
    assert_match(/Invalid character/, call("2 + a"))
  end

  def test_unbalanced_parenthesis_returns_error
    assert_match(/Expected '\)'/, call("(1 + 2"))
  end

  def test_trailing_token_returns_error
    assert_match(/Unexpected token/, call("1 2"))
  end

  def test_empty_expression_returns_error
    assert_match(/Unexpected token/, call(""))
  end

  def test_accepts_symbol_keys
    assert_equal "5", Rixie::Tool::Calculator.call({expression: "2 + 3"})
  end
end
