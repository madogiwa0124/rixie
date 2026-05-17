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

  def make_agent(responses, tools: [], max_steps: 10, stream: false, parallel_tool_calls: false)
    Rixie::Agent.new(
      instructions: "Be helpful.",
      tools: tools,
      max_steps: max_steps,
      parallel_tool_calls: parallel_tool_calls,
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

  def test_think_does_not_emit_thought_completed_for_tool_call_thought
    received = []
    listener.on(Rixie::Event::ThoughtCompleted) { |e| received << e }

    tool = simple_tool(name: "get_weather", result: "sunny")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "get_weather"), finish_response],
      tools: [tool]
    )
    agent.think(messages: [], listener: listener)

    tool_call_events = received.select { |e| e.thought.tool_call? }
    assert_empty tool_call_events
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

  def test_think_emits_tool_call_start_for_each_tool_call_before_execution
    received = []
    listener.on(Rixie::Event::ToolCallStart) { |e| received << e }

    tool = simple_tool(name: "get_weather", result: "sunny")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "get_weather"), finish_response],
      tools: [tool]
    )
    agent.think(messages: [], listener: listener)

    assert_equal 1, received.size
    assert_equal "get_weather", received.first.tool_call.name
    assert_equal "c1", received.first.tool_call.id
  end

  def test_think_emits_tool_call_end_for_each_tool_call_after_execution
    received = []
    listener.on(Rixie::Event::ToolCallEnd) { |e| received << e }

    tool = simple_tool(name: "get_weather", result: "sunny")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "get_weather"), finish_response],
      tools: [tool]
    )
    agent.think(messages: [], listener: listener)

    assert_equal 1, received.size
    assert_equal "get_weather", received.first.tool_call.name
    assert_equal({tool_call_id: "c1", content: "sunny"}, received.first.result)
  end

  def test_think_emits_step_completed_after_all_tool_calls_complete
    received = []
    listener.on(Rixie::Event::StepCompleted) { |e| received << e }

    tool = simple_tool(name: "get_weather", result: "sunny")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "get_weather"), finish_response],
      tools: [tool]
    )
    agent.think(messages: [], listener: listener)

    assert_equal 1, received.size
    assert_equal 1, received.first.tool_calls.size
    assert_equal [{tool_call_id: "c1", content: "sunny"}], received.first.tool_results
  end

  def test_think_emits_tool_call_start_before_tool_call_end
    events = []
    listener.on(Rixie::Event::ToolCallStart) { |e| events << e }
    listener.on(Rixie::Event::ToolCallEnd) { |e| events << e }

    tool = simple_tool(name: "get_weather", result: "sunny")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "get_weather"), finish_response],
      tools: [tool]
    )
    agent.think(messages: [], listener: listener)

    assert_equal 2, events.size
    assert_instance_of Rixie::Event::ToolCallStart, events[0]
    assert_instance_of Rixie::Event::ToolCallEnd, events[1]
  end

  def test_think_with_parallel_tool_calls_executes_concurrently
    slow_tool = Rixie::Tool.new(
      name: "slow",
      description: "slow tool",
      input_schema: {},
      call: ->(_) {
        sleep(0.1)
        "done"
      }
    )

    responses = [
      {
        "choices" => [{
          "message" => {
            "content" => nil,
            "tool_calls" => [
              {"id" => "c1", "function" => {"name" => "slow", "arguments" => "{}"}},
              {"id" => "c2", "function" => {"name" => "slow", "arguments" => "{}"}}
            ]
          }
        }]
      },
      finish_response
    ]

    parallel_agent = make_agent(responses, tools: [slow_tool], parallel_tool_calls: true)
    sequential_agent = make_agent(responses, tools: [slow_tool], parallel_tool_calls: false)

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    parallel_agent.think(messages: [], listener: listener)
    parallel_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    sequential_agent.think(messages: [], listener: Rixie::EventListener.new)
    sequential_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

    assert parallel_time < sequential_time, "Parallel (#{parallel_time.round(3)}s) should be faster than sequential (#{sequential_time.round(3)}s)"
  end

  def test_think_with_parallel_tool_calls_false_executes_sequentially
    order = []
    tool_a = Rixie::Tool.new(name: "a", description: "d", input_schema: {}, call: ->(_) {
      order << :a
      "a"
    })
    tool_b = Rixie::Tool.new(name: "b", description: "d", input_schema: {}, call: ->(_) {
      order << :b
      "b"
    })

    responses = [
      {
        "choices" => [{
          "message" => {
            "content" => nil,
            "tool_calls" => [
              {"id" => "c1", "function" => {"name" => "a", "arguments" => "{}"}},
              {"id" => "c2", "function" => {"name" => "b", "arguments" => "{}"}}
            ]
          }
        }]
      },
      finish_response
    ]

    agent = make_agent(responses, tools: [tool_a, tool_b], parallel_tool_calls: false)
    agent.think(messages: [], listener: listener)

    assert_equal [:a, :b], order
  end

  def test_think_with_parallel_tool_calls_raises_when_a_tool_raises
    boom_tool = Rixie::Tool.new(name: "boom", description: "d", input_schema: {}, call: ->(_) { raise "tool failed" })

    responses = [
      {
        "choices" => [{
          "message" => {
            "content" => nil,
            "tool_calls" => [
              {"id" => "c1", "function" => {"name" => "boom", "arguments" => "{}"}},
              {"id" => "c2", "function" => {"name" => "boom", "arguments" => "{}"}}
            ]
          }
        }]
      }
    ]

    agent = make_agent(responses, tools: [boom_tool], parallel_tool_calls: true)
    err = assert_raises(RuntimeError) { agent.think(messages: [], listener: listener) }
    assert_equal "tool failed", err.message
  end

  def test_think_with_parallel_tool_calls_all_threads_finish_before_raising
    finished = []
    latch = Mutex.new

    slow_boom_tool = Rixie::Tool.new(name: "slow_boom", description: "d", input_schema: {}, call: ->(_) {
      sleep(0.05)
      latch.synchronize { finished << Thread.current.object_id }
      raise "tool failed"
    })

    responses = [
      {
        "choices" => [{
          "message" => {
            "content" => nil,
            "tool_calls" => [
              {"id" => "c1", "function" => {"name" => "slow_boom", "arguments" => "{}"}},
              {"id" => "c2", "function" => {"name" => "slow_boom", "arguments" => "{}"}}
            ]
          }
        }]
      }
    ]

    agent = make_agent(responses, tools: [slow_boom_tool], parallel_tool_calls: true)
    assert_raises(RuntimeError) { agent.think(messages: [], listener: listener) }
    assert_equal 2, finished.size
  end

  def test_with_llm_client_preserves_parallel_tool_calls
    agent = make_agent([finish_response], parallel_tool_calls: true)
    new_client = make_client([finish_response])
    new_agent = agent.with_llm_client(new_client)

    assert_equal true, new_agent.parallel_tool_calls
  end
end
