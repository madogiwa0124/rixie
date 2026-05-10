# frozen_string_literal: true

require "test_helper"

class EventListenerTest < Minitest::Test
  def setup
    super
    @listener = Rixie::EventListener.new
  end

  def test_on_and_emit_calls_block_with_payload
    received = nil
    @listener.on(:finished) { |payload| received = payload }
    @listener.emit(:finished, {content: "done"})
    assert_equal({content: "done"}, received)
  end

  def test_multiple_subscribers_all_get_called
    calls = []
    @listener.on(:step_completed) { |p| calls << :first }
    @listener.on(:step_completed) { |p| calls << :second }
    @listener.emit(:step_completed, {})
    assert_equal [:first, :second], calls
  end

  def test_on_returns_self_for_chaining
    result = @listener.on(:finished) {}
    assert_same @listener, result
  end

  def test_emit_with_no_subscribers_does_nothing
    assert_silent { @listener.emit(:unknown_event, {}) }
  end
end
