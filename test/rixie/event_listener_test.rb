# frozen_string_literal: true

require "test_helper"

class EventListenerTest < Minitest::Test
  def setup
    super
    @listener = Rixie::EventListener.new
  end

  def test_on_and_emit_calls_block_with_event
    received = nil
    @listener.on(Rixie::Event::Finished) { |e| received = e }
    @listener.emit(Rixie::Event::Finished.new(content: "done"))
    assert_equal "done", received.content
  end

  def test_multiple_subscribers_for_same_class_all_get_called
    calls = []
    thought = Rixie::Agent::Thought.new(type: :finish, content: "done", tool_calls: [], tool_results: nil)
    @listener.on(Rixie::Event::ThoughtCompleted) { |_| calls << :first }
    @listener.on(Rixie::Event::ThoughtCompleted) { |_| calls << :second }
    @listener.emit(Rixie::Event::ThoughtCompleted.new(thought: thought))
    assert_equal [:first, :second], calls
  end

  def test_emit_for_unsubscribed_class_does_nothing
    assert_silent { @listener.emit(Rixie::Event::Token.new(delta: "hi")) }
  end

  def test_on_returns_self_for_chaining
    result = @listener.on(Rixie::Event::Finished) {}
    assert_same @listener, result
  end

  def test_different_event_classes_dispatched_independently
    token_calls = []
    finished_calls = []
    @listener.on(Rixie::Event::Token) { |e| token_calls << e.delta }
    @listener.on(Rixie::Event::Finished) { |e| finished_calls << e.content }

    @listener.emit(Rixie::Event::Token.new(delta: "hello"))
    @listener.emit(Rixie::Event::Finished.new(content: "done"))

    assert_equal ["hello"], token_calls
    assert_equal ["done"], finished_calls
  end
end
