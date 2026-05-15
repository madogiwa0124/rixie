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

  def make_client(responses, stream: false)
    Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", stream: stream, adapter: Rixie::LLM::Adapter::Dummy.new(responses))
  end

  def make_agent(responses, tools: [], max_steps: 10, stream: false)
    Rixie::Agent.new(
      instructions: "Be helpful.",
      tools: tools,
      max_steps: max_steps,
      llm_client: make_client(responses, stream: stream)
    )
  end

  def simple_tool(name: "get_weather", result: "sunny")
    Rixie::Tool.new(name: name, description: "desc", input_schema: {}, call: ->(_) { result })
  end

  def listener
    @listener ||= Rixie::EventListener.new
  end

  def test_think_returns_think_result_with_content_when_llm_returns_finish_immediately
    agent = make_agent([finish_response(content: "Hello!")])
    result = agent.think(messages: [], listener: listener)
    assert_instance_of Rixie::Agent::ThinkResult, result
    assert_equal "Hello!", result.content
  end

  def test_think_returns_think_result_with_thoughts_collected
    tool = simple_tool(name: "search", result: "ruby docs")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "search"), finish_response],
      tools: [tool]
    )
    result = agent.think(messages: [], listener: listener)
    assert_equal "Done!", result.content
    assert_equal 2, result.thoughts.size
    assert result.thoughts[0].tool_call?
    assert_equal [{tool_call_id: "c1", content: "ruby docs"}], result.thoughts[0].tool_results
    assert result.thoughts[1].finish?
  end

  def test_think_returns_content_after_tool_execution
    tool = simple_tool(name: "lookup")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "lookup"), finish_response(content: "Final answer")],
      tools: [tool]
    )
    result = agent.think(messages: [], listener: listener)
    assert_equal "Final answer", result.content
  end

  def test_think_emits_thought_completed_for_tool_call_thought
    received = []
    listener.on(Rixie::Event::ThoughtCompleted) { |e| received << e }

    tool = simple_tool(name: "get_weather", result: "sunny")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "get_weather"), finish_response],
      tools: [tool]
    )
    agent.think(messages: [], listener: listener)

    tool_call_event = received.find { |e| e.thought.tool_call? }
    refute_nil tool_call_event
    assert_equal 1, tool_call_event.thought.tool_calls.size
    assert_equal "get_weather", tool_call_event.thought.tool_calls.first.name
    assert_equal [{tool_call_id: "c1", content: "sunny"}], tool_call_event.thought.tool_results
  end

  def test_think_emits_thought_completed_for_finish_thought
    received = []
    listener.on(Rixie::Event::ThoughtCompleted) { |e| received << e }

    agent = make_agent([finish_response(content: "All done")])
    agent.think(messages: [], listener: listener)

    finish_event = received.find { |e| e.thought.finish? }
    refute_nil finish_event
    assert_equal "All done", finish_event.thought.content
  end

  def test_think_emits_finished_with_content
    received = nil
    listener.on(Rixie::Event::Finished) { |e| received = e }

    agent = make_agent([finish_response(content: "All done")])
    agent.think(messages: [], listener: listener)

    assert_equal "All done", received.content
  end

  def test_think_raises_max_steps_exceeded_on_next_tool_call_after_budget
    tool = simple_tool
    # max_steps=2 allows 2 tool executions; the 3rd attempt raises before executing
    responses = Array.new(3) { tool_call_response(id: "c1", name: "get_weather") }
    agent = make_agent(responses, tools: [tool], max_steps: 2)

    assert_raises(Rixie::MaxStepsExceededError) do
      agent.think(messages: [], listener: listener)
    end
  end

  def test_think_does_not_raise_when_llm_finishes_at_step_boundary
    # max_steps=2 with 2 tool_calls followed by a finish — the LLM gracefully
    # terminates at the budget boundary without exceeding.
    tool = simple_tool
    responses = [
      tool_call_response(id: "c1", name: "get_weather"),
      tool_call_response(id: "c2", name: "get_weather"),
      finish_response(content: "all done")
    ]
    agent = make_agent(responses, tools: [tool], max_steps: 2)
    result = agent.think(messages: [], listener: listener)
    assert_equal "all done", result.content
  end

  def test_think_with_max_steps_zero_succeeds_when_llm_finishes_immediately
    agent = make_agent([finish_response(content: "direct answer")], max_steps: 0)
    result = agent.think(messages: [], listener: listener)
    assert_equal "direct answer", result.content
  end

  def test_think_with_max_steps_zero_raises_when_llm_returns_tool_call
    tool = simple_tool
    agent = make_agent([tool_call_response(id: "c1", name: "get_weather")], tools: [tool], max_steps: 0)
    assert_raises(Rixie::MaxStepsExceededError) do
      agent.think(messages: [], listener: listener)
    end
  end

  def test_think_emits_finished_on_return_direct_with_nil_content
    direct_tool = Rixie::Tool.new(
      name: "submit",
      description: "d",
      input_schema: {},
      call: ->(_) { "submitted" },
      return_direct: true
    )
    agent = make_agent([tool_call_response(id: "c1", name: "submit")], tools: [direct_tool])

    received = nil
    listener.on(Rixie::Event::Finished) { |e| received = e }
    agent.think(messages: [], listener: listener)

    refute_nil received
    assert_nil received.content
  end

  def test_think_emits_finished_as_the_last_event
    tool = simple_tool(name: "search", result: "ok")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "search"), finish_response(content: "Done")],
      tools: [tool]
    )

    events = []
    listener.on(Rixie::Event::ThoughtCompleted) { |e| events << e }
    listener.on(Rixie::Event::Finished) { |e| events << e }
    agent.think(messages: [], listener: listener)

    assert_instance_of Rixie::Event::Finished, events.last
  end

  def test_think_appends_tool_call_and_tool_result_messages_to_messages
    tool = simple_tool(name: "lookup", result: "found")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "lookup"), finish_response],
      tools: [tool]
    )

    messages = [Rixie::Message::User.new(content: "hello")]
    agent.think(messages: messages, listener: listener)

    assert_equal 3, messages.size
    assert_instance_of Rixie::Message::Assistant, messages[1]
    assert_nil messages[1].content
    assert_instance_of Rixie::Message::Tool, messages[2]
    assert_equal "c1", messages[2].tool_call_id
    assert_equal "found", messages[2].content
  end

  def test_llm_call_is_private
    agent = make_agent([finish_response])
    assert_raises(NoMethodError) { agent.llm_call(messages: [], listener: listener) }
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

  def test_think_emits_event_token_when_stream_client_is_used
    tokens = []
    listener.on(Rixie::Event::Token) { |e| tokens << e.delta }

    agent = make_agent([finish_response(content: "streamed!")], stream: true)
    agent.think(messages: [], listener: listener)

    assert_equal ["streamed!"], tokens
  end

  def test_with_llm_client_returns_new_agent_with_same_instructions_and_tools
    tool = simple_tool
    agent = make_agent([finish_response], tools: [tool])
    new_client = make_client([finish_response(content: "new")])
    new_agent = agent.with_llm_client(new_client)

    assert_instance_of Rixie::Agent, new_agent
    refute_same agent, new_agent
    assert_equal agent.instructions, new_agent.instructions
    assert_equal agent.tools, new_agent.tools
    assert_same new_client, new_agent.llm_client
  end
end
