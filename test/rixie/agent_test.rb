# frozen_string_literal: true

require "test_helper"

class AgentTest < Minitest::Test
  def finish_response(content: "Done!")
    {"choices" => [{"message" => {"content" => content, "tool_calls" => nil}}]}
  end

  def tool_call_response(id:, name:, arguments: {})
    {
      "choices" => [{
        "message" => {
          "content" => nil,
          "tool_calls" => [{"id" => id, "function" => {"name" => name, "arguments" => arguments.to_json}}]
        }
      }]
    }
  end

  def make_client(responses)
    Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: Rixie::LLM::Adapter::Dummy.new(responses))
  end

  def make_agent(responses, tools: [], max_steps: 10)
    Rixie::Agent.new(
      instructions: "Be helpful.",
      tools: tools,
      max_steps: max_steps,
      llm_client: make_client(responses)
    )
  end

  def simple_tool(name: "get_weather", result: "sunny")
    Rixie::Tool.new(name: name, description: "desc", input_schema: {}, call: ->(_) { result })
  end

  def listener
    @listener ||= Rixie::EventListener.new
  end

  def test_think_returns_content_when_llm_returns_finish_immediately
    agent = make_agent([finish_response(content: "Hello!")])
    result = agent.think(messages: [], listener: listener)
    assert_equal "Hello!", result
  end

  def test_think_executes_tool_and_loops_when_llm_returns_tool_call
    tool = simple_tool(name: "search", result: "ruby docs")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "search"), finish_response],
      tools: [tool]
    )
    result = agent.think(messages: [], listener: listener)
    assert_equal "Done!", result
  end

  def test_think_returns_content_after_tool_execution
    tool = simple_tool(name: "lookup")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "lookup"), finish_response(content: "Final answer")],
      tools: [tool]
    )
    assert_equal "Final answer", agent.think(messages: [], listener: listener)
  end

  def test_think_emits_step_completed_with_tool_calls_and_tool_results
    received = nil
    listener.on(:step_completed) { |p| received = p }

    tool = simple_tool(name: "get_weather", result: "sunny")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "get_weather"), finish_response],
      tools: [tool]
    )
    agent.think(messages: [], listener: listener)

    refute_nil received
    assert_equal 1, received[:tool_calls].size
    assert_equal "get_weather", received[:tool_calls].first.name
    assert_equal [{tool_call_id: "c1", content: "sunny"}], received[:tool_results]
  end

  def test_think_emits_finished_with_content
    received = nil
    listener.on(:finished) { |p| received = p }

    agent = make_agent([finish_response(content: "All done")])
    agent.think(messages: [], listener: listener)

    assert_equal({content: "All done"}, received)
  end

  def test_think_raises_max_steps_exceeded_when_step_count_reaches_max_steps
    tool = simple_tool
    responses = Array.new(3) { tool_call_response(id: "c1", name: "get_weather") }
    agent = make_agent(responses, tools: [tool], max_steps: 3)

    assert_raises(Rixie::MaxStepsExceededError) do
      agent.think(messages: [], listener: listener)
    end
  end

  def test_think_appends_tool_call_and_tool_result_messages_to_messages
    tool = simple_tool(name: "lookup", result: "found")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "lookup"), finish_response],
      tools: [tool]
    )

    messages = [{role: "user", content: "hello"}]
    agent.think(messages: messages, listener: listener)

    assert_equal 3, messages.size
    assert_equal "assistant", messages[1][:role]
    assert_nil messages[1][:content]
    assert_equal "tool", messages[2][:role]
    assert_equal "c1", messages[2][:tool_call_id]
    assert_equal "found", messages[2][:content]
  end

  def test_llm_call_is_private
    agent = make_agent([finish_response])
    assert_raises(NoMethodError) { agent.llm_call(messages: []) }
  end

  def test_think_logs_warning_when_response_is_truncated
    log_output = StringIO.new
    Rixie.config.logger = Logger.new(log_output)

    truncated = {"choices" => [{"finish_reason" => "length", "message" => {"content" => "cut off...", "tool_calls" => nil}}]}
    agent = make_agent([truncated])
    agent.think(messages: [], listener: listener)

    assert_match "finish_reason=length", log_output.string
  end

  def test_think_does_not_log_warning_for_normal_finish
    log_output = StringIO.new
    Rixie.config.logger = Logger.new(log_output)

    agent = make_agent([finish_response])
    agent.think(messages: [], listener: listener)

    refute_match "finish_reason=length", log_output.string
  end
end
