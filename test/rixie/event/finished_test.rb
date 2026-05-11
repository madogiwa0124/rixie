# frozen_string_literal: true

require "test_helper"

class EventFinishedTest < Minitest::Test
  def test_is_a_data_object
    assert_equal Data, Rixie::Event::Finished.superclass
  end

  def test_holds_content_string
    event = Rixie::Event::Finished.new(content: "Done!")
    assert_equal "Done!", event.content
  end

  def test_is_immutable
    event = Rixie::Event::Finished.new(content: "Done!")
    assert_raises(NoMethodError) { event.content = "other" }
  end
end
