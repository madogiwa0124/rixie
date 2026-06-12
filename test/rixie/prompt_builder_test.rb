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
    assert_instance_of Rixie::Message::System, messages.first
    assert_equal "Be helpful.", messages.first.content
  end

  def test_user_message_is_always_last
    messages = builder.build(user_input: "hi", instructions: "sys", context: [])
    assert_instance_of Rixie::Message::User, messages.last
    assert_equal "hi", messages.last.content
  end

  def test_builds_messages_in_correct_order
    ctx = fake_context_entry([
      Rixie::Message::User.new(content: "prev"),
      Rixie::Message::Assistant.new(content: "ans", tool_calls: [])
    ])
    messages = builder.build(user_input: "now", instructions: "sys", context: [ctx])

    types = messages.map(&:class)
    assert_equal [Rixie::Message::System, Rixie::Message::User, Rixie::Message::Assistant, Rixie::Message::User], types
  end

  def test_context_entries_are_expanded_via_to_message
    ctx1 = fake_context_entry([
      Rixie::Message::User.new(content: "q1"),
      Rixie::Message::Assistant.new(content: "a1", tool_calls: [])
    ])
    ctx2 = fake_context_entry([
      Rixie::Message::User.new(content: "q2"),
      Rixie::Message::Assistant.new(content: "a2", tool_calls: [])
    ])
    messages = builder.build(user_input: "q3", instructions: "sys", context: [ctx1, ctx2])
    assert_equal "q1", messages[1].content
    assert_equal "a1", messages[2].content
    assert_equal "q2", messages[3].content
    assert_equal "a2", messages[4].content
  end

  def test_no_context_produces_only_system_and_user_messages
    messages = builder.build(user_input: "hi", instructions: "sys", context: [])
    assert_equal 2, messages.size
  end

  def test_nil_instructions_produce_no_system_message
    messages = builder.build(user_input: "hi", instructions: nil, context: [])
    assert_equal [Rixie::Message::User], messages.map(&:class)
  end

  def test_empty_instructions_produce_no_system_message
    messages = builder.build(user_input: "hi", instructions: "", context: [])
    assert_equal [Rixie::Message::User], messages.map(&:class)
  end
end
