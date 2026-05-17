# frozen_string_literal: true

require "test_helper"

class EventToolCallEndTest < Minitest::Test
  def test_is_a_data_object
    assert_equal Data, Rixie::Event::ToolCallEnd.superclass
  end

  def test_holds_tool_call_and_result
    tool_call = Rixie::LLM::ToolCall.new(id: "c1", name: "get_weather", arguments: {"city" => "Tokyo"})
    result = {tool_call_id: "c1", content: "sunny"}
    event = Rixie::Event::ToolCallEnd.new(tool_call: tool_call, result: result)
    assert_equal tool_call, event.tool_call
    assert_equal result, event.result
  end

  def test_is_immutable
    tool_call = Rixie::LLM::ToolCall.new(id: "c1", name: "get_weather", arguments: {})
    result = {tool_call_id: "c1", content: "sunny"}
    event = Rixie::Event::ToolCallEnd.new(tool_call: tool_call, result: result)
    assert_raises(NoMethodError) { event.tool_call = nil }
    assert_raises(NoMethodError) { event.result = nil }
  end
end
