# frozen_string_literal: true

require "test_helper"

class PlanTest < Minitest::Test
  STEPS = [
    {title: "Research", description: "Gather information"},
    {title: "Draft", description: "Write the draft"},
    {title: "Review", description: "Review and finalize"}
  ]

  CURRENT = {title: "Draft", description: "Write the draft now"}

  def test_to_message_returns_a_system_message
    plan = Rixie::Context::Plan.new(steps: STEPS, current_step: CURRENT)
    messages = plan.to_message
    assert_equal 1, messages.size
    assert_equal "system", messages.first[:role]
  end

  def test_system_message_includes_all_step_titles_with_numbering
    plan = Rixie::Context::Plan.new(steps: STEPS, current_step: CURRENT)
    content = plan.to_message.first[:content]
    assert_includes content, "1. Research"
    assert_includes content, "2. Draft"
    assert_includes content, "3. Review"
  end

  def test_system_message_includes_current_step_title_and_description
    plan = Rixie::Context::Plan.new(steps: STEPS, current_step: CURRENT)
    content = plan.to_message.first[:content]
    assert_includes content, "Current step: Draft"
    assert_includes content, "Write the draft now"
  end
end
