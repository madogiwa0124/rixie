# frozen_string_literal: true

require "test_helper"

class AgentStructuredOutputTest < Minitest::Test
  SCHEMA = {
    "type" => "object",
    "properties" => {
      "title" => {"type" => "string"},
      "tags" => {"type" => "array", "items" => {"type" => "string"}}
    },
    "required" => ["title"]
  }.freeze

  def structured_output
    Rixie::Agent::StructuredOutput.new(schema: SCHEMA)
  end

  # --- parse ---

  def test_parse_returns_valid_result_for_conforming_json
    result = structured_output.parse('{"title":"Hi","tags":["a"]}')
    assert result.valid?
    assert_nil result.error
    assert_equal({"title" => "Hi", "tags" => ["a"]}, result.value)
  end

  def test_parse_returns_error_for_invalid_json
    result = structured_output.parse("not json")
    refute result.valid?
    assert_nil result.value
    assert_includes result.error, "not valid JSON"
  end

  def test_parse_returns_error_when_required_field_missing
    result = structured_output.parse('{"tags":["a"]}')
    refute result.valid?
    assert_includes result.error, "title"
  end

  def test_parse_returns_error_for_empty_content
    refute structured_output.parse("").valid?
    refute structured_output.parse(nil).valid?
    assert_includes structured_output.parse("").error, "empty"
  end

  def test_parse_validates_nested_array_item_types
    result = structured_output.parse('{"title":"t","tags":[1]}')
    refute result.valid?
    assert_includes result.error, "tags[0]"
  end

  def test_parse_rejects_top_level_type_mismatch
    result = structured_output.parse('["not","an","object"]')
    refute result.valid?
    assert_includes result.error, "expected object"
  end

  def test_parse_validates_symbol_type
    so = Rixie::Agent::StructuredOutput.new(schema: {type: :string})
    assert so.parse('"ok"').valid?

    result = so.parse("1")
    refute result.valid?
    assert_includes result.error, "expected string"
  end

  def test_parse_recurses_into_symbol_typed_object_and_array
    schema = {
      type: :object,
      properties: {tags: {type: :array, items: {type: :string}}},
      required: [:tags]
    }
    so = Rixie::Agent::StructuredOutput.new(schema: schema)
    assert so.parse('{"tags":["a"]}').valid?
    assert_includes so.parse("{}").error, "tags"
    assert_includes so.parse('{"tags":[1]}').error, "$.tags[0]"
  end

  # --- enum ---

  def test_parse_accepts_value_in_enum
    so = Rixie::Agent::StructuredOutput.new(schema: {"type" => "string", "enum" => ["a", "b"]})
    assert so.parse('"a"').valid?
  end

  def test_parse_rejects_value_not_in_enum
    so = Rixie::Agent::StructuredOutput.new(schema: {"type" => "string", "enum" => ["a", "b"]})
    result = so.parse('"c"')
    refute result.valid?
    assert_includes result.error, "$"
    assert_includes result.error, '"c"'
    assert_includes result.error, "enum"
  end

  def test_parse_rejects_array_item_not_in_items_enum
    schema = {
      "type" => "object",
      "properties" => {"tags" => {"type" => "array", "items" => {"type" => "string", "enum" => ["ruby", "rails"]}}}
    }
    so = Rixie::Agent::StructuredOutput.new(schema: schema)
    assert so.parse('{"tags":["ruby","rails"]}').valid?

    result = so.parse('{"tags":["ruby","python"]}')
    refute result.valid?
    assert_includes result.error, "$.tags[1]"
  end

  def test_parse_matches_symbol_enum_values_against_parsed_strings
    so = Rixie::Agent::StructuredOutput.new(schema: {type: "string", enum: [:ruby, :rails]})
    assert so.parse('"ruby"').valid?
    refute so.parse('"python"').valid?
  end

  def test_parse_applies_enum_without_type
    so = Rixie::Agent::StructuredOutput.new(schema: {"enum" => ["a", 1, nil]})
    assert so.parse("1").valid?
    assert so.parse("null").valid?
    refute so.parse('"b"').valid?
  end

  def test_enum_error_does_not_list_allowed_values
    so = Rixie::Agent::StructuredOutput.new(schema: {"type" => "string", "enum" => ["allowed_one"]})
    refute_includes so.parse('"x"').error, "allowed_one"
  end

  # --- correction_message ---

  def test_correction_message_includes_error_schema_and_previous_content
    msg = structured_output.correction_message("bad answer", "$.title: missing")
    assert_kind_of Rixie::Message::User, msg
    assert_includes msg.content, "did not conform"
    assert_includes msg.content, "$.title: missing"
    assert_includes msg.content, "bad answer"
    assert_includes msg.content, "title" # schema is embedded
  end
end
