# frozen_string_literal: true

require "test_helper"

class EventStepCompletedTest < Minitest::Test
  def test_is_a_data_object
    assert_equal Data, Rixie::Event::StepCompleted.superclass
  end

  def test_holds_tool_calls_and_tool_results
    tc = Object.new
    tr = {tool_call_id: "c1", content: "result"}
    event = Rixie::Event::StepCompleted.new(tool_calls: [tc], tool_results: [tr])
    assert_equal [tc], event.tool_calls
    assert_equal [tr], event.tool_results
  end

  def test_is_immutable
    event = Rixie::Event::StepCompleted.new(tool_calls: [], tool_results: [])
    assert_raises(NoMethodError) { event.tool_calls = [] }
  end
end
