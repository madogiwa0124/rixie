# frozen_string_literal: true

require "test_helper"

class EventThoughtCompletedTest < Minitest::Test
  def make_thought
    Rixie::Agent::Thought.new(type: :finish, content: "done", tool_calls: [], tool_results: nil)
  end

  def test_is_a_data_object
    assert_equal Data, Rixie::Event::ThoughtCompleted.superclass
  end

  def test_holds_thought
    thought = make_thought
    event = Rixie::Event::ThoughtCompleted.new(thought: thought)
    assert_equal thought, event.thought
  end

  def test_is_immutable
    event = Rixie::Event::ThoughtCompleted.new(thought: make_thought)
    assert_raises(NoMethodError) { event.thought = nil }
  end
end
