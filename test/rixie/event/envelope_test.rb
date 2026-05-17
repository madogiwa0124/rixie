# frozen_string_literal: true

require "test_helper"

class EventEnvelopeTest < Minitest::Test
  def build_envelope(**overrides)
    Rixie::Event::Envelope.new(event: Rixie::Event::Finished.new(content: "done"),
      occurred_at: Time.now,
      session_id: "sid",
      task_id: "tid",
      run_id: "rid",
      sequence_number: 1,
      event_id: "eid", **overrides)
  end

  def test_is_a_data_object
    assert_equal Data, Rixie::Event::Envelope.superclass
  end

  def test_holds_all_metadata_fields
    event = Rixie::Event::Finished.new(content: "done")
    now = Time.now
    envelope = Rixie::Event::Envelope.new(
      event: event, occurred_at: now,
      session_id: "sid", task_id: "tid", run_id: "rid",
      sequence_number: 42, event_id: "eid"
    )
    assert_same event, envelope.event
    assert_equal now, envelope.occurred_at
    assert_equal "sid", envelope.session_id
    assert_equal "tid", envelope.task_id
    assert_equal "rid", envelope.run_id
    assert_equal 42, envelope.sequence_number
    assert_equal "eid", envelope.event_id
  end

  def test_metadata_can_be_nil
    envelope = build_envelope(session_id: nil, task_id: nil, run_id: nil)
    assert_nil envelope.session_id
    assert_nil envelope.task_id
    assert_nil envelope.run_id
  end

  def test_is_immutable
    envelope = build_envelope
    assert_raises(NoMethodError) { envelope.session_id = "other" }
    assert_raises(NoMethodError) { envelope.occurred_at = Time.now }
  end
end
