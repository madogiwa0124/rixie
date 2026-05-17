# frozen_string_literal: true

require "test_helper"

class ThoughtTest < Minitest::Test
  def test_can_be_created_with_tool_call_type
    thought = Rixie::Agent::Thought.new(type: :tool_call, content: nil, tool_calls: [], tool_results: nil)
    assert_equal :tool_call, thought.type
    assert_nil thought.content
    assert_empty thought.tool_calls
  end

  def test_can_be_created_with_finish_type
    thought = Rixie::Agent::Thought.new(type: :finish, content: "All done.", tool_calls: [], tool_results: nil)
    assert_equal :finish, thought.type
    assert_equal "All done.", thought.content
  end

  def test_tool_call_predicate_returns_true_for_tool_call_thought
    thought = Rixie::Agent::Thought.new(type: :tool_call, content: nil, tool_calls: [], tool_results: [])
    assert thought.tool_call?
    refute thought.finish?
  end

  def test_finish_predicate_returns_true_for_finish_thought
    thought = Rixie::Agent::Thought.new(type: :finish, content: "ok", tool_calls: [], tool_results: nil)
    assert thought.finish?
    refute thought.tool_call?
  end

  def test_with_returns_a_new_thought_with_tool_results_filled
    result = Rixie::ToolExecutor::Result.new(tool_call_id: "c1", content: "ok", error: nil)
    thought = Rixie::Agent::Thought.new(type: :tool_call, content: nil, tool_calls: [], tool_results: nil)
    updated = thought.with(tool_results: [result])
    assert_nil thought.tool_results
    assert_equal [result], updated.tool_results
  end

  def test_is_immutable
    thought = Rixie::Agent::Thought.new(type: :finish, content: "done", tool_calls: [], tool_results: nil)
    assert_raises(NoMethodError) { thought.type = :tool_call }
  end

  def test_is_a_value_object
    a = Rixie::Agent::Thought.new(type: :finish, content: "done", tool_calls: [], tool_results: nil)
    b = Rixie::Agent::Thought.new(type: :finish, content: "done", tool_calls: [], tool_results: nil)
    assert_equal a, b
  end
end
