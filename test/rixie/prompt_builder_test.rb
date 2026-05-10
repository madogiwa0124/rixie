# frozen_string_literal: true

require "test_helper"

class PromptBuilderTest < Minitest::Test
  def builder
    Rixie::PromptBuilder.new
  end

  def fake_context_entry(messages)
    obj = Object.new
    obj.define_singleton_method(:to_message) { messages }
    obj
  end

  def test_system_message_is_always_first
    messages = builder.build(user_input: "hi", instructions: "Be helpful.", context: [])
    assert_equal "system", messages.first[:role]
    assert_equal "Be helpful.", messages.first[:content]
  end

  def test_user_message_is_always_last
    messages = builder.build(user_input: "hi", instructions: "sys", context: [])
    assert_equal "user", messages.last[:role]
    assert_equal "hi", messages.last[:content]
  end

  def test_builds_messages_in_correct_order
    ctx = fake_context_entry([{role: "user", content: "prev"}, {role: "assistant", content: "ans"}])
    messages = builder.build(user_input: "now", instructions: "sys", context: [ctx])

    roles = messages.map { |m| m[:role] }
    assert_equal ["system", "user", "assistant", "user"], roles
  end

  def test_context_entries_are_expanded_via_to_message
    ctx1 = fake_context_entry([{role: "user", content: "q1"}, {role: "assistant", content: "a1"}])
    ctx2 = fake_context_entry([{role: "user", content: "q2"}, {role: "assistant", content: "a2"}])
    messages = builder.build(user_input: "q3", instructions: "sys", context: [ctx1, ctx2])
    assert_equal "q1", messages[1][:content]
    assert_equal "a1", messages[2][:content]
    assert_equal "q2", messages[3][:content]
    assert_equal "a2", messages[4][:content]
  end

  def test_no_context_produces_only_system_and_user_messages
    messages = builder.build(user_input: "hi", instructions: "sys", context: [])
    assert_equal 2, messages.size
  end
end
