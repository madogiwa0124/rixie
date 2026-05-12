# frozen_string_literal: true

require "test_helper"

class SummaryTest < Minitest::Test
  def summary
    @summary ||= Rixie::Context::Summary.new(content: "Key facts discussed.")
  end

  def test_to_message_returns_system_role_message
    messages = summary.to_message
    assert_equal 1, messages.size
    assert_instance_of Rixie::Message::System, messages.first
  end

  def test_to_message_includes_content_with_prefix
    messages = summary.to_message
    assert_equal "Previous conversation summary:\nKey facts discussed.", messages.first.content
  end

  def test_to_store_returns_hash_with_type_summary
    assert_equal "summary", summary.to_store["type"]
  end

  def test_to_store_returns_hash_with_content
    assert_equal "Key facts discussed.", summary.to_store["content"]
  end
end
