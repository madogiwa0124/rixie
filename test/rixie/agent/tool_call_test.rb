# frozen_string_literal: true

require "test_helper"

class ToolCallTest < Minitest::Test
  RAW = {
    "id" => "call_abc123",
    "function" => {
      "name" => "get_weather",
      "arguments" => '{"location":"Tokyo","unit":"celsius"}'
    }
  }

  def test_build_from_raw_parses_id
    tool_call = Rixie::Agent::ToolCall.build_from_raw(RAW)
    assert_equal "call_abc123", tool_call.id
  end

  def test_build_from_raw_parses_name
    tool_call = Rixie::Agent::ToolCall.build_from_raw(RAW)
    assert_equal "get_weather", tool_call.name
  end

  def test_build_from_raw_parses_arguments_from_json_string
    tool_call = Rixie::Agent::ToolCall.build_from_raw(RAW)
    assert_equal({"location" => "Tokyo", "unit" => "celsius"}, tool_call.arguments)
  end

  def test_to_llm_format_returns_openai_wire_format
    tool_call = Rixie::Agent::ToolCall.build_from_raw(RAW)
    result = tool_call.to_llm_format

    assert_equal "call_abc123", result["id"]
    assert_equal "function", result["type"]
    assert_equal "get_weather", result["function"]["name"]
    assert_equal({"location" => "Tokyo", "unit" => "celsius"},
      JSON.parse(result["function"]["arguments"]))
  end
end
