# frozen_string_literal: true

require "test_helper"

class EventToolCallStartTest < Minitest::Test
  def test_is_a_data_object
    assert_equal Data, Rixie::Event::ToolCallStart.superclass
  end

  def test_holds_tool_call
    tool_call = Rixie::LLM::ToolCall.new(id: "c1", name: "get_weather", arguments: {"city" => "Tokyo"})
    event = Rixie::Event::ToolCallStart.new(tool_call: tool_call)
    assert_equal tool_call, event.tool_call
  end

  def test_is_immutable
    tool_call = Rixie::LLM::ToolCall.new(id: "c1", name: "get_weather", arguments: {})
    event = Rixie::Event::ToolCallStart.new(tool_call: tool_call)
    assert_raises(NoMethodError) { event.tool_call = nil }
  end
end
