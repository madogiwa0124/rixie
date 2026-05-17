# frozen_string_literal: true

require "test_helper"

class EventTaskStartTest < Minitest::Test
  def test_is_a_data_object
    assert_equal Data, Rixie::Event::TaskStart.superclass
  end

  def test_holds_user_input_and_strategy
    strategy = Object.new
    event = Rixie::Event::TaskStart.new(user_input: "Hello", strategy: strategy)
    assert_equal "Hello", event.user_input
    assert_same strategy, event.strategy
  end

  def test_is_immutable
    event = Rixie::Event::TaskStart.new(user_input: "Hello", strategy: Object.new)
    assert_raises(NoMethodError) { event.user_input = "other" }
  end
end
