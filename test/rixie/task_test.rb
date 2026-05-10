# frozen_string_literal: true

require "test_helper"

class TaskTest < Minitest::Test
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

  def make_task(agent, strategy: Rixie::Strategy::Simple.new, context: [])
    Rixie::Task.new(user_input: "Hello", agent: agent, context: context, strategy: strategy)
  end

  def test_execute_sets_status_to_completed_on_success
    task = make_task(make_agent([finish_response]))
    task.execute
    assert_equal "completed", task.status
  end

  def test_execute_sets_output_to_strategy_result
    task = make_task(make_agent([finish_response(content: "My answer")]))
    task.execute
    assert_equal "My answer", task.output
  end

  def test_execute_sets_status_to_failed_on_exception
    adapter = Rixie::LLM::Adapter::Dummy.new([])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    agent = Rixie::Agent.new(instructions: "s", llm_client: client)
    task = make_task(agent)
    assert_raises(RuntimeError) { task.execute }
    assert_equal "failed", task.status
  end

  def test_execute_reraises_exception_on_failure
    adapter = Rixie::LLM::Adapter::Dummy.new([])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    agent = Rixie::Agent.new(instructions: "s", llm_client: client)
    task = make_task(agent)
    assert_raises(RuntimeError) { task.execute }
  end

  def test_execute_subscribes_step_completed_to_runs_last_add_step
    tool = Rixie::Tool.new(name: "search", description: "s", input_schema: {}, call: ->(_) { "found" })
    agent = make_agent(
      [tool_call_response(id: "c1", name: "search"), finish_response],
      tools: [tool]
    )
    task = make_task(agent)
    task.execute

    assert_equal 1, task.runs.last.steps.size
    assert_equal "search", task.runs.last.steps.first[:tool_calls].first.name
  end

  def test_completed_returns_true_when_completed
    task = make_task(make_agent([finish_response]))
    task.execute
    assert task.completed?
  end

  def test_failed_returns_true_when_failed
    adapter = Rixie::LLM::Adapter::Dummy.new([])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    task = make_task(Rixie::Agent.new(instructions: "s", llm_client: client))
    assert_raises(RuntimeError) { task.execute }
    assert task.failed?
  end

  def test_to_history_returns_only_completed_runs_histories
    task = make_task(make_agent([finish_response(content: "Result")]))
    task.execute
    histories = task.to_history
    assert_equal 1, histories.size
    assert_instance_of Rixie::Context::History, histories.first
  end

  def test_to_history_excludes_failed_runs
    adapter = Rixie::LLM::Adapter::Dummy.new([finish_response(content: "ok")])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    agent = Rixie::Agent.new(instructions: "s", llm_client: client)
    good_run = Rixie::Run.new(user_input: "Hello", agent: agent, context: [])

    strategy = Object.new
    strategy.define_singleton_method(:run) do |task:, listener:|
      failed_run = Rixie::Run.new(user_input: task.user_input, agent: task.agent, context: task.context)
      task.runs << failed_run
      failed_run.instance_variable_set(:@status, "failed")
      task.runs << good_run
      good_run.execute(listener:)
      good_run.output
    end

    task = Rixie::Task.new(user_input: "Hello", agent: agent, context: [], strategy: strategy)
    task.execute

    histories = task.to_history
    assert_equal 1, histories.size
  end
end
