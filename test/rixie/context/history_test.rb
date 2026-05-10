# frozen_string_literal: true

require "test_helper"

class HistoryTest < Minitest::Test
  def tool_call(id: "c1", name: "search")
    Rixie::Agent::ToolCall.new(id: id, name: name, arguments: {})
  end

  def test_to_message_with_no_steps_returns_user_and_assistant_messages
    history = Rixie::Context::History.new(input: "hello", steps: [], output: "world")
    messages = history.to_message
    assert_equal 2, messages.size
    assert_equal({role: "user", content: "hello"}, messages[0])
    assert_equal({role: "assistant", content: "world"}, messages[1])
  end

  def test_to_message_with_steps_includes_tool_call_and_tool_result_messages
    tc = tool_call
    step = {tool_calls: [tc], tool_results: [{tool_call_id: "c1", content: "found"}]}
    history = Rixie::Context::History.new(input: "q", steps: [step], output: "done")
    messages = history.to_message

    assert_equal 4, messages.size
    assert_equal "user", messages[0][:role]
    assert_equal "assistant", messages[1][:role]
    assert_nil messages[1][:content]
    assert_equal "tool", messages[2][:role]
    assert_equal "assistant", messages[3][:role]
    assert_equal "done", messages[3][:content]
  end

  def test_to_message_with_multiple_steps_returns_all_in_order
    tc1 = tool_call(id: "c1", name: "search")
    tc2 = tool_call(id: "c2", name: "lookup")
    steps = [
      {tool_calls: [tc1], tool_results: [{tool_call_id: "c1", content: "r1"}]},
      {tool_calls: [tc2], tool_results: [{tool_call_id: "c2", content: "r2"}]}
    ]
    history = Rixie::Context::History.new(input: "q", steps: steps, output: "ans")
    messages = history.to_message

    roles = messages.map { |m| m[:role] }
    assert_equal ["user", "assistant", "tool", "assistant", "tool", "assistant"], roles
  end

  def test_tool_calls_are_formatted_via_to_llm_format
    tc = tool_call(id: "c1", name: "get_data")
    step = {tool_calls: [tc], tool_results: [{tool_call_id: "c1", content: "data"}]}
    history = Rixie::Context::History.new(input: "q", steps: [step], output: "done")
    messages = history.to_message

    assistant_msg = messages[1]
    assert_equal tc.to_llm_format, assistant_msg[:tool_calls].first
  end

  def test_steps_with_empty_tool_calls_are_skipped
    step = {tool_calls: [], tool_results: []}
    history = Rixie::Context::History.new(input: "q", steps: [step], output: "done")
    messages = history.to_message
    assert_equal 2, messages.size
  end
end
