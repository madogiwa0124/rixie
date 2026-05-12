# frozen_string_literal: true

require "test_helper"

class HumanInputTest < Minitest::Test
  def test_is_a_tool_instance
    assert_instance_of Rixie::Tool, Rixie::Tool::HumanInput
  end

  def test_name
    assert_equal "human_input", Rixie::Tool::HumanInput.name
  end

  def test_call_returns_question_string
    result = Rixie::Tool::HumanInput.call({"question" => "Delete the file?"})
    assert_equal "Delete the file?", result
  end

  def test_call_uses_string_keys
    result = Rixie::Tool::HumanInput.call({"question" => "Are you sure?"})
    assert_equal "Are you sure?", result
  end
end
