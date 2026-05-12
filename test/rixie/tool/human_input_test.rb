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

  def test_to_definition_returns_openai_compatible_format
    defn = Rixie::Tool::HumanInput.to_definition
    assert_equal "function", defn[:type]
    assert_equal "human_input", defn[:function][:name]
  end

  def test_to_definition_includes_question_in_properties
    props = Rixie::Tool::HumanInput.to_definition[:function][:parameters][:properties]
    assert props.key?(:question)
    assert_equal "string", props[:question][:type]
  end

  def test_to_definition_marks_question_as_required
    required = Rixie::Tool::HumanInput.to_definition[:function][:parameters][:required]
    assert_includes required, "question"
  end
end
