# frozen_string_literal: true

require "test_helper"

class LLMToolCallTest < Minitest::Test
  RAW = {
    "id" => "call_abc123",
    "function" => {
      "name" => "get_weather",
      "arguments" => '{"location":"Tokyo","unit":"celsius"}'
    }
  }

  def test_from_openai_wire_parses_id
    tool_call = Rixie::LLM::ToolCall.from_openai_wire(RAW)
    assert_equal "call_abc123", tool_call.id
  end

  def test_from_openai_wire_parses_name
    tool_call = Rixie::LLM::ToolCall.from_openai_wire(RAW)
    assert_equal "get_weather", tool_call.name
  end

  def test_from_openai_wire_parses_arguments_from_json_string
    tool_call = Rixie::LLM::ToolCall.from_openai_wire(RAW)
    assert_equal({"location" => "Tokyo", "unit" => "celsius"}, tool_call.arguments)
  end

  def test_from_openai_wire_raises_llm_error_for_invalid_arguments_json
    raw = {
      "id" => "call_abc123",
      "function" => {"name" => "get_weather", "arguments" => '{"location":'}
    }
    error = assert_raises(Rixie::LLM::Error) { Rixie::LLM::ToolCall.from_openai_wire(raw) }
    assert_includes error.message, "get_weather"
  end

  def test_to_openai_wire_returns_openai_wire_format
    tool_call = Rixie::LLM::ToolCall.from_openai_wire(RAW)
    result = tool_call.to_openai_wire

    assert_equal "call_abc123", result["id"]
    assert_equal "function", result["type"]
    assert_equal "get_weather", result["function"]["name"]
    assert_equal({"location" => "Tokyo", "unit" => "celsius"},
      JSON.parse(result["function"]["arguments"]))
  end
end
