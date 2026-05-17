# frozen_string_literal: true

require "test_helper"

class EventTaskEndTest < Minitest::Test
  def test_is_a_data_object
    assert_equal Data, Rixie::Event::TaskEnd.superclass
  end

  def test_holds_output_and_status
    event = Rixie::Event::TaskEnd.new(output: "Result", status: "completed")
    assert_equal "Result", event.output
    assert_equal "completed", event.status
  end

  def test_output_can_be_nil
    event = Rixie::Event::TaskEnd.new(output: nil, status: "failed")
    assert_nil event.output
  end

  def test_is_immutable
    event = Rixie::Event::TaskEnd.new(output: "Result", status: "completed")
    assert_raises(NoMethodError) { event.status = "failed" }
  end
end
