# frozen_string_literal: true

require "test_helper"

class EventListenerTest < Minitest::Test
  def setup
    super
    @listener = Rixie::EventListener.new
  end

  def test_on_and_emit_calls_block_with_envelope
    received = nil
    @listener.on(Rixie::Event::Finished) { |envelope| received = envelope }
    @listener.emit(Rixie::Event::Finished.new(content: "done"))
    assert_instance_of Rixie::Event::Envelope, received
    assert_equal "done", received.event.content
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
    @listener.on(Rixie::Event::Token) { |envelope| token_calls << envelope.event.delta }
    @listener.on(Rixie::Event::Finished) { |envelope| finished_calls << envelope.event.content }

    @listener.emit(Rixie::Event::Token.new(delta: "hello"))
    @listener.emit(Rixie::Event::Finished.new(content: "done"))

    assert_equal ["hello"], token_calls
    assert_equal ["done"], finished_calls
  end

  def test_envelope_has_occurred_at
    received = nil
    @listener.on(Rixie::Event::Finished) { |envelope| received = envelope }
    before = Time.now
    @listener.emit(Rixie::Event::Finished.new(content: "done"))
    after = Time.now
    assert received.occurred_at >= before
    assert received.occurred_at <= after
  end

  def test_envelope_has_session_id_from_init
    listener = Rixie::EventListener.new(session_id: "sid-123")
    received = nil
    listener.on(Rixie::Event::Finished) { |envelope| received = envelope }
    listener.emit(Rixie::Event::Finished.new(content: "done"))
    assert_equal "sid-123", received.session_id
  end

  def test_envelope_has_task_id_from_init
    listener = Rixie::EventListener.new(task_id: "tid-456")
    received = nil
    listener.on(Rixie::Event::Finished) { |envelope| received = envelope }
    listener.emit(Rixie::Event::Finished.new(content: "done"))
    assert_equal "tid-456", received.task_id
  end

  def test_envelope_has_run_id_from_setter
    received = nil
    @listener.on(Rixie::Event::Finished) { |envelope| received = envelope }
    @listener.run_id = "rid-789"
    @listener.emit(Rixie::Event::Finished.new(content: "done"))
    assert_equal "rid-789", received.run_id
  end

  def test_envelope_run_id_is_nil_before_setter
    received = nil
    @listener.on(Rixie::Event::Finished) { |envelope| received = envelope }
    @listener.emit(Rixie::Event::Finished.new(content: "done"))
    assert_nil received.run_id
  end

  def test_sequence_number_increments_with_each_emit
    received = []
    @listener.on(Rixie::Event::Token) { |envelope| received << envelope }
    @listener.emit(Rixie::Event::Token.new(delta: "a"))
    @listener.emit(Rixie::Event::Token.new(delta: "b"))
    @listener.emit(Rixie::Event::Token.new(delta: "c"))
    assert_equal [1, 2, 3], received.map(&:sequence_number)
  end

  def test_each_envelope_has_unique_event_id
    received = []
    @listener.on(Rixie::Event::Token) { |envelope| received << envelope }
    @listener.emit(Rixie::Event::Token.new(delta: "a"))
    @listener.emit(Rixie::Event::Token.new(delta: "b"))
    assert_equal 2, received.map(&:event_id).uniq.size
  end
end
