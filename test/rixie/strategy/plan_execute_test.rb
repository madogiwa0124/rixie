# frozen_string_literal: true

require "test_helper"

class PlanExecuteTest < Minitest::Test
  STEPS = [
    {"title" => "Step 1", "description" => "Do step 1"},
    {"title" => "Step 2", "description" => "Do step 2"}
  ]

  def finish_response(content: "Done.")
    {"choices" => [{"message" => {"content" => content, "tool_calls" => nil}}]}
  end

  # The plan phase uses structured output: the planning turn is a finish whose
  # content is a JSON object matching Agent::Plan::PLAN_SCHEMA.
  def plan_response(steps: STEPS)
    finish_response(content: JSON.generate({"steps" => steps}))
  end

  def make_agent(responses)
    adapter = Rixie::LLM::Adapter::Dummy.new(responses)
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    Rixie::Agent.new(instructions: "Be helpful.", llm_client: client)
  end

  def make_task(agent, strategy: Rixie::Strategy::PlanExecute.new)
    Rixie::Task.new(user_input: "Write a report", agent: agent, context: [], strategy: strategy)
  end

  def full_responses(steps: STEPS)
    [
      plan_response(steps: steps),
      *steps.each_with_index.map { |_, i| finish_response(content: "Step #{i + 1} done.") }
    ]
  end

  # --- plan_phase ---

  def test_plan_phase_creates_run_with_agent_plan_as_agent
    agent = make_agent(full_responses)
    task = make_task(agent)
    task.execute
    assert_equal 3, task.runs.size  # 1 plan + 2 execute
    assert_instance_of Rixie::Agent::Plan, task.runs.first.agent
  end

  def test_plan_phase_appends_run_to_task_runs
    agent = make_agent(full_responses)
    task = make_task(agent)
    task.execute
    # First run is the plan run
    assert task.runs.first.completed?
  end

  # --- execute_phase ---

  def test_execute_phase_creates_one_run_per_step
    agent = make_agent(full_responses)
    task = make_task(agent)
    task.execute
    # 1 plan run + 2 execute runs = 3
    assert_equal 3, task.runs.size
  end

  def test_execute_phase_appends_each_run_to_task_runs
    agent = make_agent(full_responses)
    task = make_task(agent)
    task.execute
    assert task.runs.all?(&:completed?)
  end

  def test_execute_phase_passes_context_plan_to_each_run
    agent = make_agent(full_responses)
    task = make_task(agent)
    task.execute

    execute_run_1 = task.runs[1]
    execute_run_2 = task.runs[2]

    assert_equal 1, execute_run_1.context.count { |c| c.is_a?(Rixie::Context::Plan) }
    assert_equal 1, execute_run_2.context.count { |c| c.is_a?(Rixie::Context::Plan) }
  end

  def test_execute_phase_passes_correct_current_step_to_each_run
    agent = make_agent(full_responses)
    task = make_task(agent)
    task.execute

    plan_ctx_1 = task.runs[1].context.find { |c| c.is_a?(Rixie::Context::Plan) }
    plan_ctx_2 = task.runs[2].context.find { |c| c.is_a?(Rixie::Context::Plan) }

    msg_1 = plan_ctx_1.to_message.first.content
    msg_2 = plan_ctx_2.to_message.first.content

    assert_includes msg_1, "Current step: Step 1"
    assert_includes msg_2, "Current step: Step 2"
  end

  def test_execute_phase_accumulates_previous_step_histories_in_context
    agent = make_agent(full_responses)
    task = make_task(agent)
    task.execute

    # Step 2 の context には Step 1 の History が含まれている
    run_2_context = task.runs[2].context
    assert_equal 1, run_2_context.count { |c| c.is_a?(Rixie::Context::History) }
    history = run_2_context.find { |c| c.is_a?(Rixie::Context::History) }
    assert_equal "Step 1 done.", history.to_message.last.content
  end

  # --- extract_plan ---

  def test_extract_plan_returns_plan_with_correct_steps
    agent = make_agent(full_responses)
    task = make_task(agent)
    task.execute

    plan_run = task.runs.first
    assert_equal STEPS, plan_run.output["steps"]
  end

  def test_extract_plan_raises_agent_error_when_output_is_not_a_steps_hash
    strategy = Rixie::Strategy::PlanExecute.new
    # A run whose output is a plain string (no structured plan) must be rejected.
    adapter = Rixie::LLM::Adapter::Dummy.new([finish_response(content: "no plan here")])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    agent = Rixie::Agent.new(instructions: "s", llm_client: client)
    run = Rixie::Run.new(user_input: "x", agent: agent, context: [])
    listener = Rixie::EventListener.new
    run.execute(listener:)

    assert_raises(Rixie::AgentError) do
      strategy.send(:extract_plan, run)
    end
  end

  # --- run return value ---

  def test_run_returns_output_of_last_run
    agent = make_agent(full_responses)
    task = make_task(agent)
    task.execute
    assert_equal "Step 2 done.", task.output
  end

  # --- full integration ---

  def test_full_integration_plan_plus_two_execute_steps
    agent = make_agent(full_responses)
    task = make_task(agent)
    task.execute

    assert task.completed?
    assert_equal 3, task.runs.size
    assert task.runs.all?(&:completed?)
    assert_equal "Step 2 done.", task.output
  end

  def test_run_executes_plan_phase_then_execute_phase
    agent = make_agent(full_responses)
    task = make_task(agent)
    task.execute

    # plan run uses Agent::Plan, execute runs use the base agent
    assert_instance_of Rixie::Agent::Plan, task.runs[0].agent
    assert_same agent, task.runs[1].agent
    assert_same agent, task.runs[2].agent
  end
end
