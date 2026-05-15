# frozen_string_literal: true

require "test_helper"

class HistoryTest < Minitest::Test
  def tool_call(id: "c1", name: "search")
    Rixie::LLM::ToolCall.new(id: id, name: name, arguments: {})
  end

  def tool_call_thought(tool_calls:, tool_results:)
    Rixie::Agent::Thought.new(type: :tool_call, content: nil, tool_calls: tool_calls, tool_results: tool_results)
  end

  def finish_thought(content:)
    Rixie::Agent::Thought.new(type: :finish, content: content, tool_calls: [], tool_results: nil)
  end

  def test_to_message_with_no_thoughts_returns_user_and_assistant_messages
    history = Rixie::Context::History.new(input: "hello", thoughts: [], output: "world")
    messages = history.to_message
    assert_equal 2, messages.size
    assert_instance_of Rixie::Message::User, messages[0]
    assert_equal "hello", messages[0].content
    assert_instance_of Rixie::Message::Assistant, messages[1]
    assert_equal "world", messages[1].content
  end

  def test_to_message_with_tool_call_thought_includes_tool_call_and_tool_result_messages
    tc = tool_call
    thought = tool_call_thought(tool_calls: [tc], tool_results: [{tool_call_id: "c1", content: "found"}])
    history = Rixie::Context::History.new(input: "q", thoughts: [thought], output: "done")
    messages = history.to_message

    assert_equal 4, messages.size
    assert_instance_of Rixie::Message::User, messages[0]
    assert_instance_of Rixie::Message::Assistant, messages[1]
    assert_nil messages[1].content
    assert_instance_of Rixie::Message::Tool, messages[2]
    assert_instance_of Rixie::Message::Assistant, messages[3]
    assert_equal "done", messages[3].content
  end

  def test_to_message_with_multiple_thoughts_returns_all_in_order
    tc1 = tool_call(id: "c1", name: "search")
    tc2 = tool_call(id: "c2", name: "lookup")
    thoughts = [
      tool_call_thought(tool_calls: [tc1], tool_results: [{tool_call_id: "c1", content: "r1"}]),
      tool_call_thought(tool_calls: [tc2], tool_results: [{tool_call_id: "c2", content: "r2"}])
    ]
    history = Rixie::Context::History.new(input: "q", thoughts: thoughts, output: "ans")
    messages = history.to_message

    types = messages.map(&:class)
    assert_equal [
      Rixie::Message::User,
      Rixie::Message::Assistant,
      Rixie::Message::Tool,
      Rixie::Message::Assistant,
      Rixie::Message::Tool,
      Rixie::Message::Assistant
    ], types
  end

  def test_assistant_message_contains_tool_call_objects
    tc = tool_call(id: "c1", name: "get_data")
    thought = tool_call_thought(tool_calls: [tc], tool_results: [{tool_call_id: "c1", content: "data"}])
    history = Rixie::Context::History.new(input: "q", thoughts: [thought], output: "done")
    messages = history.to_message

    assistant_msg = messages[1]
    assert_equal [tc], assistant_msg.tool_calls
  end

  def test_thoughts_with_empty_tool_calls_are_skipped
    thought = tool_call_thought(tool_calls: [], tool_results: [])
    history = Rixie::Context::History.new(input: "q", thoughts: [thought], output: "done")
    messages = history.to_message
    assert_equal 2, messages.size
  end

  def test_finish_thoughts_in_thoughts_are_skipped_in_messages
    thought = finish_thought(content: "intermediate")
    history = Rixie::Context::History.new(input: "q", thoughts: [thought], output: "done")
    messages = history.to_message
    assert_equal 2, messages.size
  end
end
