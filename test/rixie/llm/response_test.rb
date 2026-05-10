# frozen_string_literal: true

require "test_helper"

class ResponseTest < Minitest::Test
  OPENAI_WITH_TOOL_CALLS = {
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

  OPENAI_FINISH = {
    "choices" => [{"message" => {"content" => "Hello!", "tool_calls" => nil}}]
  }

  ANTHROPIC_WITH_TOOL_CALLS = {
    "content" => [
      {"type" => "tool_use", "id" => "toolu_01", "name" => "get_weather", "input" => {"location" => "Tokyo"}},
      {"type" => "text", "text" => "Let me check."}
    ]
  }

  ANTHROPIC_FINISH = {
    "content" => [{"type" => "text", "text" => "Hello from Anthropic!"}]
  }

  def test_has_tool_calls_returns_true_when_present
    response = Rixie::LLM::Response.new(raw: OPENAI_WITH_TOOL_CALLS, provider: :openai)
    assert response.has_tool_calls?
  end

  def test_has_tool_calls_returns_false_when_absent
    response = Rixie::LLM::Response.new(raw: OPENAI_FINISH, provider: :openai)
    refute response.has_tool_calls?
  end

  def test_content_returns_text
    response = Rixie::LLM::Response.new(raw: OPENAI_FINISH, provider: :openai)
    assert_equal "Hello!", response.content
  end

  def test_normalizes_openai_tool_calls
    response = Rixie::LLM::Response.new(raw: OPENAI_WITH_TOOL_CALLS, provider: :openai)
    tc = response.tool_calls.first
    assert_equal "call_abc", tc["id"]
    assert_equal "get_weather", tc["function"]["name"]
    assert_equal '{"location":"Tokyo"}', tc["function"]["arguments"]
  end

  def test_normalizes_openai_content_as_nil_when_tool_calling
    response = Rixie::LLM::Response.new(raw: OPENAI_WITH_TOOL_CALLS, provider: :openai)
    assert_nil response.content
  end

  def test_normalizes_anthropic_tool_calls
    response = Rixie::LLM::Response.new(raw: ANTHROPIC_WITH_TOOL_CALLS, provider: :anthropic)
    assert response.has_tool_calls?
    tc = response.tool_calls.first
    assert_equal "toolu_01", tc["id"]
    assert_equal "get_weather", tc["function"]["name"]
    assert_equal({location: "Tokyo"}.to_json, tc["function"]["arguments"])
  end

  def test_normalizes_anthropic_text_content
    response = Rixie::LLM::Response.new(raw: ANTHROPIC_WITH_TOOL_CALLS, provider: :anthropic)
    assert_equal "Let me check.", response.content
  end

  def test_normalizes_anthropic_finish
    response = Rixie::LLM::Response.new(raw: ANTHROPIC_FINISH, provider: :anthropic)
    refute response.has_tool_calls?
    assert_equal "Hello from Anthropic!", response.content
  end
end
