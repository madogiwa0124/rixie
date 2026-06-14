# frozen_string_literal: true

require "test_helper"

class EventLlmCallEndTest < Minitest::Test
  def test_is_a_data_object
    assert_equal Data, Rixie::Event::LlmCallEnd.superclass
  end

  def test_holds_usage_and_finish_reason
    usage = {input_tokens: 100, output_tokens: 50}
    event = Rixie::Event::LlmCallEnd.new(usage: usage, finish_reason: "stop")
    assert_equal usage, event.usage
    assert_equal "stop", event.finish_reason
  end

  def test_usage_input_and_output_tokens_accessible
    event = Rixie::Event::LlmCallEnd.new(
      usage: {input_tokens: 200, output_tokens: 75},
      finish_reason: "stop"
    )
    assert_equal 200, event.usage[:input_tokens]
    assert_equal 75, event.usage[:output_tokens]
  end

  def test_is_immutable
    event = Rixie::Event::LlmCallEnd.new(usage: {input_tokens: 10, output_tokens: 5}, finish_reason: "stop")
    assert_raises(NoMethodError) { event.usage = {} }
  end
end
