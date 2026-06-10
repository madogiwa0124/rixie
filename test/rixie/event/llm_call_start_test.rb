# frozen_string_literal: true

require "test_helper"

class EventLlmCallStartTest < Minitest::Test
  def test_is_a_data_object
    assert_equal Data, Rixie::Event::LlmCallStart.superclass
  end

  def test_holds_step_count_model_and_provider
    event = Rixie::Event::LlmCallStart.new(step_count: 3, model: "gpt-4o", provider: "openai")
    assert_equal 3, event.step_count
    assert_equal "gpt-4o", event.model
    assert_equal "openai", event.provider
  end

  def test_is_immutable
    event = Rixie::Event::LlmCallStart.new(step_count: 1, model: "gpt-4o", provider: "openai")
    assert_raises(NoMethodError) { event.step_count = 2 }
  end
end
