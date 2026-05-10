# frozen_string_literal: true

require "test_helper"

class ResponseTest < Minitest::Test
  WITH_TOOL_CALLS = {
    "choices" => [{
      "message" => {
        "content" => nil,
        "tool_calls" => [
          {
            "id" => "call_abc",
            "function" => {"name" => "get_weather", "arguments" => '{"location":"Tokyo"}'}
          }
        ]
      }
    }]
  }

  WITH_TOOL_CALLS_AND_TEXT = {
    "choices" => [{
      "message" => {
        "content" => "Let me check.",
        "tool_calls" => [
          {
            "id" => "call_abc",
            "function" => {"name" => "get_weather", "arguments" => '{"location":"Tokyo"}'}
          }
        ]
      }
    }]
  }

  FINISH = {
    "choices" => [{"message" => {"content" => "Hello!", "tool_calls" => nil}}]
  }

  def test_has_tool_calls_returns_true_when_present
    response = Rixie::LLM::Response.new(raw: WITH_TOOL_CALLS)
    assert response.has_tool_calls?
  end

  def test_has_tool_calls_returns_false_when_absent
    response = Rixie::LLM::Response.new(raw: FINISH)
    refute response.has_tool_calls?
  end

  def test_content_returns_text
    response = Rixie::LLM::Response.new(raw: FINISH)
    assert_equal "Hello!", response.content
  end

  def test_parses_tool_calls
    response = Rixie::LLM::Response.new(raw: WITH_TOOL_CALLS)
    tc = response.tool_calls.first
    assert_equal "call_abc", tc["id"]
    assert_equal "get_weather", tc["function"]["name"]
    assert_equal '{"location":"Tokyo"}', tc["function"]["arguments"]
  end

  def test_content_is_nil_when_only_tool_calls
    response = Rixie::LLM::Response.new(raw: WITH_TOOL_CALLS)
    assert_nil response.content
  end

  def test_content_when_tool_calls_and_text_coexist
    response = Rixie::LLM::Response.new(raw: WITH_TOOL_CALLS_AND_TEXT)
    assert_equal "Let me check.", response.content
  end

  def test_finish_has_no_tool_calls
    response = Rixie::LLM::Response.new(raw: FINISH)
    refute response.has_tool_calls?
    assert_equal "Hello!", response.content
  end

  def test_finish_reason_returns_value_from_raw
    raw = {"choices" => [{"finish_reason" => "stop", "message" => {"content" => "Hi", "tool_calls" => nil}}]}
    response = Rixie::LLM::Response.new(raw: raw)
    assert_equal "stop", response.finish_reason
  end

  def test_finish_reason_returns_nil_when_absent
    response = Rixie::LLM::Response.new(raw: FINISH)
    assert_nil response.finish_reason
  end
end
