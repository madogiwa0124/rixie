# frozen_string_literal: true

require "test_helper"

class EventLlmCallStartTest < Minitest::Test
  def test_is_a_data_object
    assert_equal Data, Rixie::Event::LlmCallStart.superclass
  end

  def test_holds_model_and_provider
    event = Rixie::Event::LlmCallStart.new(model: "gpt-4o", provider: "openai")
    assert_equal "gpt-4o", event.model
    assert_equal "openai", event.provider
  end

  def test_is_immutable
    event = Rixie::Event::LlmCallStart.new(model: "gpt-4o", provider: "openai")
    assert_raises(NoMethodError) { event.model = "gpt-4" }
  end
end
