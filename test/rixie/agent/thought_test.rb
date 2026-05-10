# frozen_string_literal: true

require "test_helper"

class ThoughtTest < Minitest::Test
  def test_can_be_created_with_tool_call_type
    thought = Rixie::Agent::Thought.new(type: :tool_call, content: nil, tool_calls: [])
    assert_equal :tool_call, thought.type
    assert_nil thought.content
    assert_empty thought.tool_calls
  end

  def test_can_be_created_with_finish_type
    thought = Rixie::Agent::Thought.new(type: :finish, content: "All done.", tool_calls: [])
    assert_equal :finish, thought.type
    assert_equal "All done.", thought.content
  end

  def test_is_immutable
    thought = Rixie::Agent::Thought.new(type: :finish, content: "done", tool_calls: [])
    assert_raises(NoMethodError) { thought.type = :tool_call }
  end

  def test_is_a_value_object
    a = Rixie::Agent::Thought.new(type: :finish, content: "done", tool_calls: [])
    b = Rixie::Agent::Thought.new(type: :finish, content: "done", tool_calls: [])
    assert_equal a, b
  end
end
