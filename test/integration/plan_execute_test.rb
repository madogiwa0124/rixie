# frozen_string_literal: true

require_relative "test_helper"

# Scenario: PlanExecute strategy — plan phase followed by per-step execution.
# Verifies that planning, plan extraction, context injection per step,
# and multi-run orchestration work correctly end-to-end.
#
# Note: live mode requires the LLM to return a plan as structured output
# (a JSON object matching Agent::Plan::PLAN_SCHEMA).
class PlanExecuteTest < Integration::TestCase
  STEPS = [
    {"title" => "Research", "description" => "Gather information on the topic."},
    {"title" => "Write", "description" => "Compose the summary based on research."}
  ].freeze

  def responses_for_full_flow
    [
      plan_response(steps: STEPS),               # plan phase: structured-output plan
      finish_response(content: "Research complete."),  # execute step 1
      finish_response(content: "Summary written.")     # execute step 2
    ]
  end

  def test_full_plan_and_execute_flow
    client = build_client(responses: responses_for_full_flow)
    session = Rixie::Session.new(
      instructions: "You are a helpful assistant.",
      llm_client: client
    )

    output = session.chat("Write a summary about Ruby.", strategy: Rixie::Strategy::PlanExecute.new)

    task = session.tasks.first
    assert task.completed?
    assert_instance_of String, output
    refute_empty output

    unless live?
      assert_equal 3, task.runs.size  # 1 plan run + 2 execute runs
      assert task.runs.all?(&:completed?)
      assert_equal "Summary written.", output
    end
  end

  def test_plan_run_uses_agent_plan
    client = build_client(responses: responses_for_full_flow)
    session = Rixie::Session.new(
      instructions: "You are a helpful assistant.",
      llm_client: client
    )

    session.chat("Write a summary about Ruby.", strategy: Rixie::Strategy::PlanExecute.new)

    unless live?
      assert_instance_of Rixie::Agent::Plan, session.tasks.first.runs.first.agent
    end
  end

  def test_each_execute_step_receives_plan_in_context
    client = build_client(responses: responses_for_full_flow)
    session = Rixie::Session.new(
      instructions: "You are a helpful assistant.",
      llm_client: client
    )

    session.chat("Write a summary about Ruby.", strategy: Rixie::Strategy::PlanExecute.new)

    unless live?
      execute_runs = session.tasks.first.runs[1..]
      execute_runs.each do |run|
        plan_contexts = run.context.select { |c| c.is_a?(Rixie::Context::Plan) }
        assert_equal 1, plan_contexts.size
      end
    end
  end

  def test_step2_context_includes_step1_history
    client = build_client(responses: responses_for_full_flow)
    session = Rixie::Session.new(
      instructions: "You are a helpful assistant.",
      llm_client: client
    )

    session.chat("Write a summary about Ruby.", strategy: Rixie::Strategy::PlanExecute.new)

    unless live?
      step2_run = session.tasks.first.runs[2]
      history_contexts = step2_run.context.select { |c| c.is_a?(Rixie::Context::History) }
      assert_equal 1, history_contexts.size
      assert_equal "Research complete.", history_contexts.first.instance_variable_get(:@output)
    end
  end
end
