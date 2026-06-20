# frozen_string_literal: true

require "test_helper"

class RunTest < Minitest::Test
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

  def make_agent(responses, tools: [])
    adapter = Rixie::LLM::Adapter::Dummy.new(responses)
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    Rixie::Agent.new(instructions: "Be helpful.", tools: tools, llm_client: client)
  end

  def make_run(agent, context: [])
    Rixie::Run.new(user_input: "Hello", agent: agent, context: context)
  end

  def listener
    @listener ||= Rixie::EventListener.new
  end

  def test_execute_calls_agent_think_with_built_messages
    agent = make_agent([finish_response])
    run = make_run(agent)
    run.execute(listener: listener)
    assert run.completed?
  end

  def test_execute_sets_status_to_completed_on_success
    run = make_run(make_agent([finish_response]))
    run.execute(listener: listener)
    assert_equal "completed", run.status
  end

  def test_execute_sets_output_to_agent_think_return_value
    run = make_run(make_agent([finish_response(content: "The answer")]))
    run.execute(listener: listener)
    assert_equal "The answer", run.output
  end

  def test_execute_sets_status_to_failed_on_exception
    adapter = Rixie::LLM::Adapter::Dummy.new([])  # will raise when exhausted
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    agent = Rixie::Agent.new(instructions: "sys", llm_client: client)
    run = make_run(agent)

    assert_raises(RuntimeError) { run.execute(listener: listener) }
    assert_equal "failed", run.status
  end

  def test_execute_reraises_exception_on_failure
    adapter = Rixie::LLM::Adapter::Dummy.new([])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    agent = Rixie::Agent.new(instructions: "sys", llm_client: client)
    run = make_run(agent)

    assert_raises(RuntimeError) { run.execute(listener: listener) }
  end

  def test_execute_populates_thoughts_from_think_result
    tool = Rixie::Tool.new(name: "search", description: "s", input_schema: {}, call: ->(_) { "found" })
    agent = make_agent(
      [tool_call_response(id: "c1", name: "search"), finish_response],
      tools: [tool]
    )
    run = make_run(agent)
    run.execute(listener: listener)

    assert_equal 2, run.thoughts.size
    assert run.thoughts[0].tool_call?
    assert_equal "search", run.thoughts[0].tool_calls.first.name
    r = run.thoughts[0].tool_results.first
    assert_equal "c1", r.tool_call_id
    assert_equal "found", r.content
    assert run.thoughts[1].finish?
  end

  def test_completed_returns_true_when_status_is_completed
    run = make_run(make_agent([finish_response]))
    run.execute(listener: listener)
    assert run.completed?
  end

  def test_failed_returns_true_when_status_is_failed
    adapter = Rixie::LLM::Adapter::Dummy.new([])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    run = make_run(Rixie::Agent.new(instructions: "s", llm_client: client))
    assert_raises(RuntimeError) { run.execute(listener: listener) }
    assert run.failed?
  end

  def test_to_history_returns_context_history_with_correct_data
    run = make_run(make_agent([finish_response(content: "Answer")]))
    run.execute(listener: listener)
    history = run.to_history
    assert_instance_of Rixie::Context::History, history
    messages = history.to_message
    assert_equal "Hello", messages.first.content
    assert_equal "Answer", messages.last.content
  end

  def test_listener_receives_tool_calls_completed_events_during_execute
    tool = Rixie::Tool.new(name: "search", description: "s", input_schema: {}, call: ->(_) { "found" })
    agent = make_agent(
      [tool_call_response(id: "c1", name: "search"), finish_response],
      tools: [tool]
    )
    run = make_run(agent)

    received = []
    listener.on(Rixie::Event::ToolCallsCompleted) { |envelope| received << envelope }
    run.execute(listener: listener)

    assert_equal 1, received.size
    assert_equal "search", received.first.event.tool_calls.first.name
  end

  def test_execute_emits_run_start_at_beginning
    received = []
    listener.on(Rixie::Event::RunStart) { |envelope| received << envelope }

    run = make_run(make_agent([finish_response]))
    run.execute(listener: listener)

    assert_equal 1, received.size
    assert_equal "Hello", received.first.event.user_input
  end

  def test_execute_emits_run_end_with_completed_on_success
    received = []
    listener.on(Rixie::Event::RunEnd) { |envelope| received << envelope }

    run = make_run(make_agent([finish_response(content: "Done")]))
    run.execute(listener: listener)

    assert_equal 1, received.size
    assert_equal "completed", received.first.event.status
    assert_equal "Done", received.first.event.output
  end

  def test_execute_emits_run_end_with_failed_on_failure
    received = []
    listener.on(Rixie::Event::RunEnd) { |envelope| received << envelope }

    adapter = Rixie::LLM::Adapter::Dummy.new([])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    run = make_run(Rixie::Agent.new(instructions: "s", llm_client: client))

    assert_raises(RuntimeError) { run.execute(listener: listener) }
    assert_equal 1, received.size
    assert_equal "failed", received.first.event.status
    assert_nil received.first.event.output
  end
end
