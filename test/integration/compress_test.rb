# frozen_string_literal: true

require_relative "test_helper"

# Scenario: context compression via Session#compress!
# Verifies that compress! summarizes history, clears tasks, preserves
# recent entries when requested, and that conversation continues correctly
# with the compressed context.
class CompressTest < Integration::TestCase
  def test_compress_replaces_history_with_summary
    client = build_client(responses: [
      finish_response(content: "The capital of France is Paris."),
      finish_response(content: "Summary: discussed that Paris is the capital of France.")
    ])
    session = Rixie::Session.new(instructions: "You are a helpful assistant.", llm_client: client)

    session.chat("What is the capital of France?")
    session.compress!

    assert_equal 1, session.context.size
    assert_instance_of Rixie::Context::Summary, session.context.first
    assert_equal [], session.tasks
    unless live?
      assert_equal "Summary: discussed that Paris is the capital of France.", session.context.first.content
    end
  end

  def test_conversation_continues_after_compress
    client = build_client(responses: [
      finish_response(content: "The capital of France is Paris."),
      finish_response(content: "Summary: user asked about France's capital."),
      finish_response(content: "Based on our earlier discussion, the capital is Paris.")
    ])
    session = Rixie::Session.new(instructions: "You are a helpful assistant.", llm_client: client)

    session.chat("What is the capital of France?")
    session.compress!
    output = session.chat("Can you repeat what we discussed?")

    assert_instance_of String, output
    refute_empty output
    assert_equal 1, session.tasks.size
    assert_equal 2, session.context.size
    assert_instance_of Rixie::Context::Summary, session.context.first
    assert_instance_of Rixie::Context::History, session.context.last
  end

  def test_compress_with_keep_recent_preserves_recent_entries
    client = build_client(responses: [
      finish_response(content: "Turn 1"),
      finish_response(content: "Turn 2"),
      finish_response(content: "Turn 3"),
      finish_response(content: "Summary of turn 1.")
    ])
    session = Rixie::Session.new(instructions: "You are a helpful assistant.", llm_client: client)

    session.chat("Message 1")
    session.chat("Message 2")
    session.chat("Message 3")
    session.compress!(keep_recent: 2)

    ctx = session.context
    assert_instance_of Rixie::Context::Summary, ctx.first
    recent = ctx.select { |e| e.is_a?(Rixie::Context::History) }
    assert_equal 2, recent.size
    unless live?
      assert_equal "Message 2", recent.first.instance_variable_get(:@input)
      assert_equal "Message 3", recent.last.instance_variable_get(:@input)
    end
  end

  def test_compress_persists_to_store_and_loads_correctly
    store = Rixie::Store::Memory.new
    client = build_client(responses: [
      finish_response(content: "42 is the answer."),
      finish_response(content: "Summary: the answer is 42.")
    ])
    session = Rixie::Session.new(
      instructions: "You are a helpful assistant.",
      llm_client: client,
      store: store
    )

    session.chat("What is the answer to life?")
    session.compress!

    session_id = session.instance_variable_get(:@session_id)
    loaded = store.load(session_id)
    assert_equal 1, loaded.size
    assert_instance_of Rixie::Context::Summary, loaded.first
  end

  def test_compress_is_no_op_when_context_is_empty
    client = build_client(responses: [])
    session = Rixie::Session.new(instructions: "You are a helpful assistant.", llm_client: client)

    session.compress!

    assert_equal [], session.context
    assert_nil session.instance_variable_get(:@summary)
  end

  def test_context_size_reflects_content_length
    client = build_client(responses: [finish_response(content: "Hello!")])
    session = Rixie::Session.new(instructions: "You are a helpful assistant.", llm_client: client)

    assert_equal 0, session.context_size
    session.chat("Hi")
    assert session.context_size > 0
  end

  def test_context_size_decreases_after_compress
    client = build_client(responses: [
      finish_response(content: "A" * 400),
      finish_response(content: "Short summary.")
    ])
    session = Rixie::Session.new(instructions: "You are a helpful assistant.", llm_client: client)

    session.chat("Tell me something long.")
    size_before = session.context_size

    session.compress!
    size_after = session.context_size

    assert size_after < size_before unless live?
  end
end
