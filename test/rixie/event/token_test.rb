# frozen_string_literal: true

require "test_helper"

class EventTokenTest < Minitest::Test
  def test_is_a_data_object
    assert_equal Data, Rixie::Event::Token.superclass
  end

  def test_holds_delta_string
    token = Rixie::Event::Token.new(delta: "hello")
    assert_equal "hello", token.delta
  end

  def test_is_immutable
    token = Rixie::Event::Token.new(delta: "hi")
    assert_raises(NoMethodError) { token.delta = "other" }
  end
end
