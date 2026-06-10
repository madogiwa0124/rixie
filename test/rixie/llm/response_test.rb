# frozen_string_literal: true

require "test_helper"

class ResponseTest < Minitest::Test
  def make_tool_call(id: "call_abc", name: "get_weather")
    Rixie::LLM::ToolCall.new(id: id, name: name, arguments: {"location" => "Tokyo"})
  end

  def test_has_tool_calls_returns_true_when_present
    response = Rixie::LLM::Response.new(content: nil, tool_calls: [make_tool_call], finish_reason: nil, usage: nil)
    assert response.has_tool_calls?
  end

  def test_has_tool_calls_returns_false_when_absent
    response = Rixie::LLM::Response.new(content: "Hello!", tool_calls: [], finish_reason: "stop", usage: nil)
    refute response.has_tool_calls?
  end

  def test_content_returns_text
    response = Rixie::LLM::Response.new(content: "Hello!", tool_calls: [], finish_reason: "stop", usage: nil)
    assert_equal "Hello!", response.content
  end

  def test_tool_calls_returns_tool_call_objects
    tc = make_tool_call
    response = Rixie::LLM::Response.new(content: nil, tool_calls: [tc], finish_reason: nil, usage: nil)
    assert_equal [tc], response.tool_calls
  end

  def test_content_is_nil_when_only_tool_calls
    response = Rixie::LLM::Response.new(content: nil, tool_calls: [make_tool_call], finish_reason: nil, usage: nil)
    assert_nil response.content
  end

  def test_finish_reason_returns_value
    response = Rixie::LLM::Response.new(content: "Hi", tool_calls: [], finish_reason: "stop", usage: nil)
    assert_equal "stop", response.finish_reason
  end

  def test_finish_reason_returns_nil_when_absent
    response = Rixie::LLM::Response.new(content: "Hello!", tool_calls: [], finish_reason: nil, usage: nil)
    assert_nil response.finish_reason
  end

  def test_usage_returns_nil_when_absent
    response = Rixie::LLM::Response.new(content: "Hello!", tool_calls: [], finish_reason: "stop", usage: nil)
    assert_nil response.usage
  end

  def test_usage_returns_normalized_hash_when_present
    usage = {input_tokens: 100, output_tokens: 50}
    response = Rixie::LLM::Response.new(content: "Hi", tool_calls: [], finish_reason: "stop", usage: usage)
    assert_equal 100, response.usage[:input_tokens]
    assert_equal 50, response.usage[:output_tokens]
  end

  def test_from_openai_wire_parses_usage_when_present
    raw = {
      "choices" => [{"finish_reason" => "stop", "message" => {"content" => "Hi", "tool_calls" => nil}}],
      "usage" => {"prompt_tokens" => 120, "completion_tokens" => 40}
    }
    response = Rixie::LLM::Response.from_openai_wire(raw)
    assert_equal 120, response.usage[:input_tokens]
    assert_equal 40, response.usage[:output_tokens]
  end

  def test_from_openai_wire_usage_is_nil_when_absent
    raw = {
      "choices" => [{"finish_reason" => "stop", "message" => {"content" => "Hi", "tool_calls" => nil}}]
    }
    response = Rixie::LLM::Response.from_openai_wire(raw)
    assert_nil response.usage
  end
end
