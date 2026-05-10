# frozen_string_literal: true

require_relative "test_helper"

# Scenario: basic single/multi-turn conversation via Session#chat.
# Verifies that Session wires up Agent, Task, Run, and context accumulation
# correctly end-to-end.
class SimpleChatTest < Integration::TestCase
  def test_single_turn_returns_a_string_response
    client = build_client(responses: [finish_response(content: "Hello!")])
    session = Rixie::Session.new(
      instructions: "Reply with exactly 'Hello!' and nothing else.",
      llm_client: client
    )

    output = session.chat("Hi")

    assert_instance_of String, output
    refute_empty output
    assert_equal "Hello!", output unless live?
  end

  def test_single_turn_creates_one_completed_task
    client = build_client(responses: [finish_response])
    session = Rixie::Session.new(instructions: "Be helpful.", llm_client: client)

    session.chat("Hello")

    assert_equal 1, session.tasks.size
    assert session.tasks.first.completed?
  end

  def test_multi_turn_context_is_accumulated
    client = build_client(responses: [
      finish_response(content: "Got it, the number is 42."),
      finish_response(content: "The number you told me is 42.")
    ])
    session = Rixie::Session.new(instructions: "You are a helpful assistant.", llm_client: client)

    session.chat("Remember this number: 42. Confirm you got it.")
    output = session.chat("What number did I ask you to remember?")

    assert_equal 2, session.tasks.size
    assert session.tasks.all?(&:completed?)
    assert_instance_of String, output
    refute_empty output
    assert_equal "The number you told me is 42.", output unless live?
  end

  def test_multi_turn_previous_history_is_in_context
    client = build_client(responses: [finish_response(content: "Turn 1"), finish_response(content: "Turn 2")])
    session = Rixie::Session.new(instructions: "Be helpful.", llm_client: client)

    session.chat("First message")
    session.chat("Second message")

    assert_equal 2, session.context.size
    assert session.context.all? { |c| c.is_a?(Rixie::Context::History) }
  end

  def test_failed_task_is_excluded_from_context
    client = build_client(responses: [finish_response(content: "OK")])
    session = Rixie::Session.new(instructions: "Be helpful.", llm_client: client)

    failed_task = Rixie::Task.new(
      user_input: "This failed",
      agent: session.agent,
      context: [],
      strategy: Rixie::Strategy::Simple.new
    )
    failed_task.instance_variable_set(:@status, "failed")
    session.tasks << failed_task

    session.chat("Hello")

    assert_equal 1, session.context.size
    assert_equal "Hello", session.context.first.instance_variable_get(:@input)
  end
end
