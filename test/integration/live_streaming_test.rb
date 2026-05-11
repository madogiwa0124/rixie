# frozen_string_literal: true

require_relative "test_helper"

# Scenario: Session#live streaming interface.
# Verifies that live returns a lazy Enumerator, emits typed Event objects,
# and correctly updates task/context state after full enumeration — end-to-end
# through Session → Task → Agent → LLM::Client → Adapter.
class LiveStreamingTest < Integration::TestCase
  def weather_tool
    Rixie::Tool.new(
      name: "get_weather",
      description: "Returns current weather for a given city.",
      input_schema: {
        "type" => "object",
        "properties" => {"city" => {"type" => "string"}},
        "required" => ["city"]
      },
      call: ->(args) { "Sunny, 25°C in #{args["city"]}" }
    )
  end

  def make_session(chat_responses: [], stream_responses: [], tools: [])
    Rixie::Session.new(
      instructions: "Be helpful.",
      tools: tools,
      llm_client: build_client(responses: chat_responses),
      stream_client: build_stream_client(responses: stream_responses)
    )
  end

  # --- structural tests (always run) ---

  def test_live_returns_enumerator
    session = make_session(stream_responses: [finish_response])
    assert_instance_of Enumerator, session.live("Hi")
  end

  def test_live_does_not_execute_before_iteration
    session = make_session(stream_responses: [finish_response])
    _enum = session.live("Hi")
    assert_equal 0, session.tasks.size
  end

  def test_live_appends_completed_task_after_full_enumeration
    session = make_session(stream_responses: [finish_response(content: "Done.")])
    session.live("Hi").to_a

    assert_equal 1, session.tasks.size
    assert session.tasks.first.completed?
  end

  def test_live_persists_context_after_enumeration
    session = make_session(stream_responses: [finish_response(content: "Done.")])
    session.live("Hi").to_a

    assert_equal 1, session.context.size
    assert_instance_of Rixie::Context::History, session.context.first
  end

  def test_live_accumulates_context_across_multiple_calls
    session = make_session(
      stream_responses: [
        finish_response(content: "First."),
        finish_response(content: "Second.")
      ]
    )

    session.live("First message").to_a
    session.live("Second message").to_a

    assert_equal 2, session.tasks.size
    assert_equal 2, session.context.size
    assert session.tasks.all?(&:completed?)
  end

  def test_live_context_feeds_into_subsequent_chat
    session = make_session(
      chat_responses: [finish_response(content: "Chat reply.")],
      stream_responses: [finish_response(content: "Streamed reply.")]
    )

    session.live("Stream this").to_a
    session.chat("Now chat")

    assert_equal 2, session.tasks.size
    assert_equal 2, session.context.size
  end

  # --- event emission tests ---

  def test_live_yields_only_typed_event_objects
    session = make_session(stream_responses: [finish_response])
    events = session.live("Hi").to_a

    assert events.all? { |e|
      e.is_a?(Rixie::Event::Token) ||
        e.is_a?(Rixie::Event::StepCompleted) ||
        e.is_a?(Rixie::Event::Finished)
    }
  end

  def test_live_yields_exactly_one_finished_event
    session = make_session(stream_responses: [finish_response(content: "Final.")])
    events = session.live("Hi").to_a

    finished = events.select { |e| e.is_a?(Rixie::Event::Finished) }
    assert_equal 1, finished.size

    unless live?
      assert_equal "Final.", finished.first.content
    end
  end

  def test_live_yields_event_token_for_text_content
    session = make_session(stream_responses: [finish_response(content: "Hello!")])
    events = session.live("Hi").to_a

    tokens = events.select { |e| e.is_a?(Rixie::Event::Token) }

    # At minimum one token should be emitted for non-empty content.
    # (DummyAdapter emits the full content as a single token.)
    refute_empty tokens unless live?
    assert tokens.all? { |e| e.delta.is_a?(String) }

    unless live?
      assert_equal "Hello!", tokens.map(&:delta).join
    end
  end

  def test_live_finished_content_matches_joined_tokens
    session = make_session(stream_responses: [finish_response(content: "Streaming output.")])
    events = session.live("Hi").to_a

    tokens = events.select { |e| e.is_a?(Rixie::Event::Token) }
    finished = events.find { |e| e.is_a?(Rixie::Event::Finished) }

    refute_nil finished
    unless live?
      assert_equal finished.content, tokens.map(&:delta).join
    end
  end

  def test_live_finished_event_is_last
    session = make_session(stream_responses: [finish_response(content: "Done.")])
    events = session.live("Hi").to_a

    assert_instance_of Rixie::Event::Finished, events.last
  end

  # --- tool use ---

  def test_live_with_tool_use_yields_step_completed
    session = make_session(
      tools: [weather_tool],
      stream_responses: [
        tool_call_response(id: "c1", name: "get_weather", arguments: {"city" => "Tokyo"}),
        finish_response(content: "It's sunny in Tokyo.")
      ]
    )
    events = session.live("What's the weather in Tokyo?").to_a

    step_events = events.select { |e| e.is_a?(Rixie::Event::StepCompleted) }
    assert_equal 1, step_events.size

    unless live?
      step = step_events.first
      assert_equal 1, step.tool_calls.size
      assert_equal "get_weather", step.tool_calls.first.name
      assert_equal [{tool_call_id: "c1", content: "Sunny, 25°C in Tokyo"}], step.tool_results
    end
  end

  def test_live_with_tool_use_step_completed_precedes_finished
    session = make_session(
      tools: [weather_tool],
      stream_responses: [
        tool_call_response(id: "c1", name: "get_weather", arguments: {"city" => "Tokyo"}),
        finish_response(content: "Sunny.")
      ]
    )
    events = session.live("Weather in Tokyo?").to_a

    finished_index = events.index { |e| e.is_a?(Rixie::Event::Finished) }
    refute_nil finished_index

    # In live mode the LLM may choose not to call the tool, so only assert ordering in dummy mode.
    unless live?
      step_index = events.index { |e| e.is_a?(Rixie::Event::StepCompleted) }
      refute_nil step_index
      assert step_index < finished_index
    end
  end

  def test_live_with_tool_use_adds_step_to_run
    session = make_session(
      tools: [weather_tool],
      stream_responses: [
        tool_call_response(id: "c1", name: "get_weather", arguments: {"city" => "Osaka"}),
        finish_response(content: "Cloudy in Osaka.")
      ]
    )
    session.live("Weather in Osaka?").to_a

    run = session.tasks.first.runs.first
    assert_equal 1, run.steps.size unless live?
  end

  # --- strategy ---

  def test_live_accepts_strategy_argument
    session = make_session(stream_responses: [finish_response(content: "Simple.")])
    events = session.live("Hi", strategy: Rixie::Strategy::Simple.new).to_a

    assert events.any? { |e| e.is_a?(Rixie::Event::Finished) }
  end
end
