# frozen_string_literal: true

require "test_helper"

class EventRunStartTest < Minitest::Test
  def test_is_a_data_object
    assert_equal Data, Rixie::Event::RunStart.superclass
  end

  def test_holds_user_input
    event = Rixie::Event::RunStart.new(user_input: "Hello")
    assert_equal "Hello", event.user_input
  end

  def test_is_immutable
    event = Rixie::Event::RunStart.new(user_input: "Hello")
    assert_raises(NoMethodError) { event.user_input = "other" }
  end
end
