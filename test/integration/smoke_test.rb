# frozen_string_literal: true

require_relative "test_helper"

# Broad smoke test covering all major features in one file.
# Designed to run quickly against a real LLM — each test makes the minimum
# number of LLM calls needed to exercise the feature.
class SmokeTest < Integration::TestCase
  def weather_tool
    Rixie::Tool.new(
      name: "get_weather",
      description: "Returns current weather for a city.",
      input_schema: {
        type: "object",
        properties: {city: {type: "string"}},
        required: ["city"]
      },
      call: ->(args) { "Sunny, 22°C in #{args["city"]}" }
    )
  end

  # --- chat ---

  def test_chat_returns_string
    client = build_client(responses: [finish_response(content: "Paris.")])
    session = Rixie::Session.new(
      instructions: "Reply with a single word: the capital of France.",
      llm_client: client
    )

    output = session.chat("What is the capital of France?")

    assert_instance_of String, output
    refute_empty output
    assert session.tasks.first.completed?
    assert_equal "Paris.", output unless live?
  end

  # --- tool use ---

  def test_tool_use_calls_tool_and_returns_answer
    client = build_client(responses: [
      tool_call_response(id: "tc1", name: "get_weather", arguments: {"city" => "Tokyo"}),
      finish_response(content: "It is sunny in Tokyo.")
    ])
    session = Rixie::Session.new(
      instructions: "You are a weather assistant.",
      tools: [weather_tool],
      llm_client: client
    )

    output = session.chat("What's the weather in Tokyo?")
    task = session.tasks.first
    run = task.runs.first

    assert task.completed?
    assert_equal 1, run.steps.size
    assert_equal "get_weather", run.steps.first[:tool_calls].first.name
    assert_instance_of String, output
    assert_match(/Tokyo/i, output) if live?
    assert_equal "It is sunny in Tokyo.", output unless live?
  end

  # --- live streaming ---

  def test_live_yields_token_and_finished_events
    stream_client = build_stream_client(responses: [finish_response(content: "Hello!")])
    session = Rixie::Session.new(
      instructions: "Reply with exactly 'Hello!'",
      llm_client: build_client(responses: []),
      stream_client: stream_client
    )

    events = session.live("Say hello.").to_a
    tokens = events.select { |e| e.is_a?(Rixie::Event::Token) }
    finished = events.find { |e| e.is_a?(Rixie::Event::Finished) }

    assert_instance_of Rixie::Event::Finished, finished
    refute_empty finished.content
    refute_empty tokens unless live? # dummy emits 1 token; real LLM may vary
    assert session.tasks.first.completed?
    assert_equal "Hello!", finished.content unless live?
  end

  # --- PlanExecute strategy ---

  def test_plan_execute_produces_output
    client = build_client(responses: [
      plan_done_response(steps: [
        {"title" => "Step 1", "description" => "Do the first thing."},
        {"title" => "Step 2", "description" => "Do the second thing."}
      ]),
      finish_response(content: "Step 1 done."),
      finish_response(content: "Step 2 done.")
    ])
    session = Rixie::Session.new(
      instructions: "You are a helpful assistant.",
      llm_client: client
    )

    output = session.chat("Do a two-step task.", strategy: Rixie::Strategy::PlanExecute.new)
    task = session.tasks.first

    assert task.completed?
    assert_instance_of String, output
    refute_empty output
    unless live?
      assert_equal 3, task.runs.size # 1 planning run + 2 execution runs
      assert_equal "Step 2 done.", output
    end
  end
end
