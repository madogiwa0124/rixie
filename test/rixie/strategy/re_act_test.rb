# frozen_string_literal: true

require "test_helper"

class ReActStrategyTest < Minitest::Test
  def finish_response(content: "Done!")
    {"choices" => [{"message" => {"content" => content, "tool_calls" => nil}}]}
  end

  def make_agent(responses)
    adapter = Rixie::LLM::Adapter::Dummy.new(responses)
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    Rixie::Agent.new(instructions: "Be helpful.", llm_client: client)
  end

  def make_task(agent, context: [])
    Rixie::Task.new(
      user_input: "Hello",
      agent: agent,
      context: context,
      strategy: Rixie::Strategy::ReAct.new
    )
  end

  def listener
    @listener ||= Rixie::EventListener.new
  end

  def test_run_wraps_task_agent_with_react
    agent = make_agent([finish_response])
    task = make_task(agent)
    Rixie::Strategy::ReAct.new.run(task: task, listener: listener)

    run = task.runs.first
    assert_instance_of Rixie::Agent::ReAct, run.agent
  end

  def test_run_passes_user_input_and_context_to_run
    agent = make_agent([finish_response])
    task = make_task(agent, context: [])
    Rixie::Strategy::ReAct.new.run(task: task, listener: listener)

    run = task.runs.first
    assert_equal "Hello", run.user_input
    assert_equal [], run.context
  end

  def test_run_appends_run_to_task_runs
    task = make_task(make_agent([finish_response]))
    assert_equal 0, task.runs.size
    Rixie::Strategy::ReAct.new.run(task: task, listener: listener)
    assert_equal 1, task.runs.size
  end

  def test_run_executes_the_run
    task = make_task(make_agent([finish_response]))
    Rixie::Strategy::ReAct.new.run(task: task, listener: listener)
    assert task.runs.first.completed?
  end

  def test_run_returns_run_output
    task = make_task(make_agent([finish_response(content: "Answer")]))
    result = Rixie::Strategy::ReAct.new.run(task: task, listener: listener)
    assert_equal "Answer", result
  end
end
