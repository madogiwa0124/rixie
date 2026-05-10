# frozen_string_literal: true

require "test_helper"

class SimpleStrategyTest < Minitest::Test
  def finish_response(content: "Done!")
    raw = {"choices" => [{"message" => {"content" => content, "tool_calls" => nil}}]}
    Rixie::LLM::Response.new(raw: raw, provider: :openai)
  end

  def make_agent(responses)
    adapter = DummyAdapter.new(responses)
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    Rixie::Agent.new(instructions: "Be helpful.", llm_client: client)
  end

  def make_task(agent, context: [])
    Rixie::Task.new(
      user_input: "Hello",
      agent: agent,
      context: context,
      strategy: Rixie::Strategy::Simple.new
    )
  end

  def listener
    @listener ||= Rixie::EventListener.new
  end

  def test_run_creates_run_with_correct_user_input_agent_and_context
    agent = make_agent([finish_response])
    task = make_task(agent, context: [])
    strategy = Rixie::Strategy::Simple.new
    strategy.run(task: task, listener: listener)

    run = task.runs.first
    assert_equal "Hello", run.user_input
    assert_same agent, run.agent
    assert_equal [], run.context
  end

  def test_run_appends_run_to_task_runs
    task = make_task(make_agent([finish_response]))
    strategy = Rixie::Strategy::Simple.new
    assert_equal 0, task.runs.size
    strategy.run(task: task, listener: listener)
    assert_equal 1, task.runs.size
  end

  def test_run_executes_the_run
    task = make_task(make_agent([finish_response]))
    strategy = Rixie::Strategy::Simple.new
    strategy.run(task: task, listener: listener)
    assert task.runs.first.completed?
  end

  def test_run_returns_run_output
    task = make_task(make_agent([finish_response(content: "Answer")]))
    strategy = Rixie::Strategy::Simple.new
    result = strategy.run(task: task, listener: listener)
    assert_equal "Answer", result
  end
end
