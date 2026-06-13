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
    r = result.thoughts[0].tool_results.first
    assert_equal "c1", r.tool_call_id
    assert_equal "ruby docs", r.content
    assert r.success?
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
    listener.on(Rixie::Event::ThoughtCompleted) { |envelope| received << envelope }

    tool = simple_tool(name: "get_weather", result: "sunny")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "get_weather"), finish_response],
      tools: [tool]
    )
    agent.think(messages: [], listener: listener)

    tool_call_events = received.select { |envelope| envelope.event.thought.tool_call? }
    assert_empty tool_call_events
  end

  def test_think_emits_thought_completed_for_finish_thought
    received = []
    listener.on(Rixie::Event::ThoughtCompleted) { |envelope| received << envelope }

    agent = make_agent([finish_response(content: "All done")])
    agent.think(messages: [], listener: listener)

    finish_event = received.find { |envelope| envelope.event.thought.finish? }
    refute_nil finish_event
    assert_equal "All done", finish_event.event.thought.content
  end

  def test_think_emits_finished_with_content
    received = nil
    listener.on(Rixie::Event::Finished) { |envelope| received = envelope }

    agent = make_agent([finish_response(content: "All done")])
    agent.think(messages: [], listener: listener)

    assert_equal "All done", received.event.content
  end

  def test_max_steps_reader_returns_configured_value
    agent = make_agent([], max_steps: 3)
    assert_equal 3, agent.max_steps
  end

  def test_max_steps_reader_returns_default_when_not_configured
    adapter = Rixie::LLM::Adapter::Dummy.new([])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    agent = Rixie::Agent.new(instructions: "...", llm_client: client)
    assert_equal Rixie::Agent::DEFAULT_MAX_STEPS, agent.max_steps
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
    listener.on(Rixie::Event::Finished) { |envelope| received = envelope }
    agent.think(messages: [], listener: listener)

    refute_nil received
    assert_nil received.event.content
  end

  def test_think_emits_finished_as_the_last_event
    tool = simple_tool(name: "search", result: "ok")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "search"), finish_response(content: "Done")],
      tools: [tool]
    )

    events = []
    listener.on(Rixie::Event::ThoughtCompleted) { |envelope| events << envelope }
    listener.on(Rixie::Event::Finished) { |envelope| events << envelope }
    agent.think(messages: [], listener: listener)

    assert_instance_of Rixie::Event::Finished, events.last.event
  end

  def test_think_does_not_mutate_caller_messages_but_grows_conversation_for_next_call
    tool = simple_tool(name: "lookup", result: "found")
    recorded = []
    adapter = Rixie::LLM::Adapter::Dummy.new([tool_call_response(id: "c1", name: "lookup"), finish_response])
    adapter.define_singleton_method(:chat) do |messages, tools:, schema: nil|
      recorded << messages
      super(messages, tools: tools, schema: schema)
    end
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    agent = Rixie::Agent.new(instructions: "Be helpful.", tools: [tool], llm_client: client)

    messages = [Rixie::Message::User.new(content: "hello")]
    agent.think(messages: messages, listener: listener)

    # The caller's array is left untouched.
    assert_equal 1, messages.size

    # The second LLM call sees the appended assistant + tool-result messages.
    second_call = recorded[1]
    assert_equal 3, second_call.size
    assert_instance_of Rixie::Message::Assistant, second_call[1]
    assert_nil second_call[1].content
    assert_instance_of Rixie::Message::Tool, second_call[2]
    assert_equal "c1", second_call[2].tool_call_id
    assert_equal "found", second_call[2].content
  end

  def test_llm_call_is_private
    agent = make_agent([finish_response])
    assert_raises(NoMethodError) { agent.llm_call(messages: []) }
  end

  def test_think_raises_response_truncated_error_when_finish_reason_is_length
    truncated = {"choices" => [{"finish_reason" => "length", "message" => {"content" => "cut off...", "tool_calls" => nil}}]}
    agent = make_agent([truncated])
    assert_raises(Rixie::LLM::ResponseTruncatedError) do
      agent.think(messages: [], listener: listener)
    end
  end

  def test_think_raises_response_truncated_error_in_stream_mode
    truncated = {"choices" => [{"finish_reason" => "length", "message" => {"content" => "cut off...", "tool_calls" => nil}}]}
    agent = make_agent([truncated], stream: true)
    assert_raises(Rixie::LLM::ResponseTruncatedError) do
      agent.think(messages: [], listener: listener)
    end
  end

  def test_think_emits_event_token_when_stream_client_is_used
    tokens = []
    listener.on(Rixie::Event::Token) { |envelope| tokens << envelope.event.delta }

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
    listener.on(Rixie::Event::ToolCallStart) { |envelope| received << envelope }

    tool = simple_tool(name: "get_weather", result: "sunny")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "get_weather"), finish_response],
      tools: [tool]
    )
    agent.think(messages: [], listener: listener)

    assert_equal 1, received.size
    assert_equal "get_weather", received.first.event.tool_call.name
    assert_equal "c1", received.first.event.tool_call.id
  end

  def test_think_emits_tool_call_end_for_each_tool_call_after_execution
    received = []
    listener.on(Rixie::Event::ToolCallEnd) { |envelope| received << envelope }

    tool = simple_tool(name: "get_weather", result: "sunny")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "get_weather"), finish_response],
      tools: [tool]
    )
    agent.think(messages: [], listener: listener)

    assert_equal 1, received.size
    assert_equal "get_weather", received.first.event.tool_call.name
    r = received.first.event.result
    assert_equal "c1", r.tool_call_id
    assert_equal "sunny", r.content
    assert r.success?
  end

  def test_think_emits_tool_calls_completed_after_all_tool_calls_complete
    received = []
    listener.on(Rixie::Event::ToolCallsCompleted) { |envelope| received << envelope }

    tool = simple_tool(name: "get_weather", result: "sunny")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "get_weather"), finish_response],
      tools: [tool]
    )
    agent.think(messages: [], listener: listener)

    assert_equal 1, received.size
    assert_equal 1, received.first.event.tool_calls.size
    r = received.first.event.tool_results.first
    assert_equal "c1", r.tool_call_id
    assert_equal "sunny", r.content
  end

  def test_think_emits_tool_call_start_before_tool_call_end
    events = []
    listener.on(Rixie::Event::ToolCallStart) { |envelope| events << envelope }
    listener.on(Rixie::Event::ToolCallEnd) { |envelope| events << envelope }

    tool = simple_tool(name: "get_weather", result: "sunny")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "get_weather"), finish_response],
      tools: [tool]
    )
    agent.think(messages: [], listener: listener)

    assert_equal 2, events.size
    assert_instance_of Rixie::Event::ToolCallStart, events[0].event
    assert_instance_of Rixie::Event::ToolCallEnd, events[1].event
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

  def test_think_emits_tool_call_end_with_error_content_when_tool_raises
    boom_tool = Rixie::Tool.new(name: "boom", description: "d", input_schema: {}, call: ->(_) { raise "tool failed" })

    received = []
    listener.on(Rixie::Event::ToolCallEnd) { |envelope| received << envelope }

    responses = [
      tool_call_response(id: "c1", name: "boom"),
      finish_response
    ]

    agent = make_agent(responses, tools: [boom_tool])
    agent.think(messages: [], listener: listener)

    assert_equal 1, received.size
    assert_equal "c1", received.first.event.tool_call.id
    assert_equal "Error: tool failed", received.first.event.result.content
    assert received.first.event.result.error?
  end

  def test_think_parallel_emits_tool_call_end_for_all_tools_when_some_raise
    boom_tool = Rixie::Tool.new(name: "boom", description: "d", input_schema: {}, call: ->(_) { raise "tool failed" })

    received = []
    listener.on(Rixie::Event::ToolCallEnd) { |envelope| received << envelope }

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
      },
      finish_response
    ]

    agent = make_agent(responses, tools: [boom_tool], parallel_tool_calls: true)
    agent.think(messages: [], listener: listener)

    assert_equal 2, received.size
    assert_equal "Error: tool failed", received[0].event.result.content
    assert_equal "Error: tool failed", received[1].event.result.content
    assert received[0].event.result.error?
    assert received[1].event.result.error?
  end

  def test_with_llm_client_preserves_parallel_tool_calls
    agent = make_agent([finish_response], parallel_tool_calls: true)
    new_client = make_client([finish_response])
    new_agent = agent.with_llm_client(new_client)

    assert_equal true, new_agent.parallel_tool_calls
  end

  def test_think_emits_llm_call_start_before_each_llm_call
    received = []
    listener.on(Rixie::Event::LlmCallStart) { |envelope| received << envelope }

    agent = make_agent([finish_response(content: "Done")])
    agent.think(messages: [], listener: listener)

    assert_equal 1, received.size
    assert_equal 1, received.first.event.step_count
    assert_equal "gpt-4o", received.first.event.model
    assert_equal "openai", received.first.event.provider
  end

  def test_think_llm_call_start_step_count_increments_across_tool_call_loops
    received = []
    listener.on(Rixie::Event::LlmCallStart) { |envelope| received << envelope }

    tool = simple_tool(name: "search", result: "ok")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "search"), finish_response],
      tools: [tool]
    )
    agent.think(messages: [], listener: listener)

    assert_equal 2, received.size
    assert_equal 1, received[0].event.step_count
    assert_equal 2, received[1].event.step_count
  end

  def test_think_emits_llm_call_end_after_each_llm_call
    received = []
    listener.on(Rixie::Event::LlmCallEnd) { |envelope| received << envelope }

    agent = make_agent([finish_response(content: "Done")])
    agent.think(messages: [], listener: listener)

    assert_equal 1, received.size
    e = received.first.event
    assert_equal 1, e.step_count
    assert_kind_of Hash, e.usage
    assert e.usage.key?(:input_tokens)
    assert e.usage.key?(:output_tokens)
  end

  def test_think_llm_call_end_step_count_increments_across_tool_call_loops
    received = []
    listener.on(Rixie::Event::LlmCallEnd) { |envelope| received << envelope }

    tool = simple_tool(name: "search", result: "ok")
    agent = make_agent(
      [tool_call_response(id: "c1", name: "search"), finish_response],
      tools: [tool]
    )
    agent.think(messages: [], listener: listener)

    assert_equal 2, received.size
    assert_equal 1, received[0].event.step_count
    assert_equal 2, received[1].event.step_count
  end

  def test_think_llm_call_end_uses_provider_usage_when_present
    received = []
    listener.on(Rixie::Event::LlmCallEnd) { |envelope| received << envelope }

    response_with_usage = {
      "choices" => [{"finish_reason" => "stop", "message" => {"content" => "Done", "tool_calls" => nil}}],
      "usage" => {"prompt_tokens" => 150, "completion_tokens" => 30}
    }
    agent = make_agent([response_with_usage])
    agent.think(messages: [], listener: listener)

    e = received.first.event
    assert_equal 150, e.usage[:input_tokens]
    assert_equal 30, e.usage[:output_tokens]
  end

  def test_think_llm_call_end_uses_estimated_usage_when_provider_omits_it
    received = []
    listener.on(Rixie::Event::LlmCallEnd) { |envelope| received << envelope }

    agent = make_agent([finish_response(content: "Done")])
    messages = [Rixie::Message::User.new(content: "Hello world")]
    agent.think(messages: messages, listener: listener)

    e = received.first.event
    assert_kind_of Integer, e.usage[:input_tokens]
    assert_kind_of Integer, e.usage[:output_tokens]
    assert e.usage[:input_tokens] >= 0
    assert e.usage[:output_tokens] >= 0
  end

  def test_think_emits_llm_call_end_before_finished
    events = []
    listener.on(Rixie::Event::LlmCallEnd) { |envelope| events << :llm_call_end }
    listener.on(Rixie::Event::Finished) { |envelope| events << :finished }

    agent = make_agent([finish_response(content: "Done")])
    agent.think(messages: [], listener: listener)

    assert_equal [:llm_call_end, :finished], events
  end

  def test_concurrent_map_re_raises_tool_not_found_error
    # ToolNotFoundError propagates through the thread rescue in concurrent_map,
    # covering the first_error non-nil branches.
    responses = [{
      "choices" => [{"message" => {
        "content" => nil,
        "tool_calls" => [{"id" => "c1", "function" => {"name" => "nonexistent", "arguments" => "{}"}}]
      }}]
    }]
    agent = make_agent(responses, tools: [], parallel_tool_calls: true)
    assert_raises(Rixie::ToolNotFoundError) { agent.think(messages: [], listener: listener) }
  end

  # --- structured output (schema:) ---

  SCHEMA = {"type" => "object", "properties" => {"answer" => {"type" => "string"}}, "required" => ["answer"]}.freeze

  def test_think_with_schema_returns_parsed_hash
    agent = make_agent([finish_response(content: '{"answer":"42"}')])
    result = agent.think(messages: [], listener: listener, schema: SCHEMA)
    assert_equal({"answer" => "42"}, result.content)
  end

  def test_think_with_schema_emits_parsed_hash_on_finished_event
    finished = nil
    listener.on(Rixie::Event::Finished) { |envelope| finished = envelope.event.content }
    agent = make_agent([finish_response(content: '{"answer":"yes"}')])
    agent.think(messages: [], listener: listener, schema: SCHEMA)
    assert_equal({"answer" => "yes"}, finished)
  end

  def test_think_with_schema_retries_finish_generation_on_invalid_json
    agent = make_agent([
      finish_response(content: "here is your answer"),
      finish_response(content: '{"answer":"recovered"}')
    ])
    result = agent.think(messages: [], listener: listener, schema: SCHEMA)
    assert_equal({"answer" => "recovered"}, result.content)
  end

  def test_think_with_schema_does_not_rerun_tool_calls_on_retry
    calls = 0
    tool = Rixie::Tool.new(name: "lookup", description: "d", input_schema: {}, call: lambda { |_|
      calls += 1
      "data"
    })
    agent = make_agent(
      [
        tool_call_response(id: "c1", name: "lookup"),
        finish_response(content: "prose, not json"),
        finish_response(content: '{"answer":"final"}')
      ],
      tools: [tool]
    )
    result = agent.think(messages: [], listener: listener, schema: SCHEMA)
    assert_equal({"answer" => "final"}, result.content)
    assert_equal 1, calls, "tool must run exactly once — the retry re-generates only the finish answer"
  end

  def test_think_with_schema_raises_when_retry_limit_exceeded
    invalid = Array.new(6) { finish_response(content: "never valid json") }
    agent = make_agent(invalid)
    assert_raises(Rixie::SchemaValidationError) do
      agent.think(messages: [], listener: listener, schema: SCHEMA)
    end
  end

  def test_think_without_schema_returns_string
    agent = make_agent([finish_response(content: "plain text")])
    result = agent.think(messages: [], listener: listener)
    assert_equal "plain text", result.content
  end
end
