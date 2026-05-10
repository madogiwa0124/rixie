# frozen_string_literal: true

require_relative "test_helper"

# Scenario: agent that has access to tools.
# Verifies that the tool call loop (Agent#think), ToolExecutor, and
# step accumulation work together correctly end-to-end.
class ToolUseTest < Integration::TestCase
  def weather_tool
    Rixie::Tool.new(
      name: "get_weather",
      description: "Returns the current weather for a given city.",
      input_schema: {
        "type" => "object",
        "properties" => {"city" => {"type" => "string", "description" => "City name"}},
        "required" => ["city"]
      },
      call: ->(args) { "Sunny, 25°C in #{args["city"]}" }
    )
  end

  def test_agent_calls_tool_then_returns_final_answer
    client = build_client(responses: [
      tool_call_response(id: "c1", name: "get_weather", arguments: {"city" => "Tokyo"}),
      finish_response(content: "The weather in Tokyo is sunny at 25°C.")
    ])
    session = Rixie::Session.new(
      instructions: "You are a weather assistant. Use get_weather to answer weather questions.",
      tools: [weather_tool],
      llm_client: client
    )

    output = session.chat("What's the weather in Tokyo?")

    task = session.tasks.first
    assert task.completed?
    assert_instance_of String, output
    refute_empty output

    unless live?
      assert_equal "The weather in Tokyo is sunny at 25°C.", output
      run = task.runs.first
      assert_equal 1, run.steps.size
      assert_equal "get_weather", run.steps.first[:tool_calls].first.name
      assert_equal "Sunny, 25°C in Tokyo", run.steps.first[:tool_results].first[:content]
    end
  end

  def test_agent_calls_multiple_tools_sequentially
    client = build_client(responses: [
      tool_call_response(id: "c1", name: "get_weather", arguments: {"city" => "Tokyo"}),
      tool_call_response(id: "c2", name: "get_weather", arguments: {"city" => "Osaka"}),
      finish_response(content: "Tokyo is sunny (25°C), Osaka is cloudy (20°C).")
    ])
    session = Rixie::Session.new(
      instructions: "You are a weather assistant. Use get_weather for each city separately.",
      tools: [weather_tool],
      llm_client: client
    )

    output = session.chat("Compare the weather in Tokyo and Osaka.")

    task = session.tasks.first
    assert task.completed?
    assert_instance_of String, output
    refute_empty output

    unless live?
      assert_equal 2, task.runs.first.steps.size
      cities = task.runs.first.steps.map { |s| s[:tool_calls].first.arguments["city"] }
      assert_equal %w[Tokyo Osaka], cities
    end
  end
end
