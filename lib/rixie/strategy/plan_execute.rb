# frozen_string_literal: true

module Rixie
  module Strategy
    class PlanExecute
      Plan = Data.define(:steps)

      def run(task:, listener:)
        plan = plan_phase(task:, listener:)
        execute_phase(plan:, task:, listener:)
        task.runs.last.output
      end

      private

      def plan_phase(task:, listener:)
        run = Run.new(
          user_input: task.user_input,
          agent: Agent::Plan.new(base_agent: task.agent),
          context: task.context
        )
        task.runs << run
        run.execute(listener:)
        extract_plan(run)
      end

      def execute_phase(plan:, task:, listener:)
        completed_histories = []

        plan.steps.each_with_index do |step, index|
          last_step = index == plan.steps.size - 1
          run = Run.new(
            user_input: task.user_input,
            agent: task.agent,
            context: task.context + completed_histories + [
              Context::Plan.new(steps: plan.steps, current_step: step)
            ],
            # The schema constrains only the final answer — intermediate steps run unconstrained.
            schema: last_step ? task.schema : nil
          )
          task.runs << run
          run.execute(listener:)
          completed_histories << run.to_history if run.completed?
        end
      end

      # The plan run uses `Agent::Plan`, which produces the plan as structured
      # output — so `run.output` is a Hash matching `Agent::Plan::PLAN_SCHEMA`.
      def extract_plan(run)
        raw_steps = run.output.is_a?(Hash) ? run.output["steps"] : nil

        raise AgentError, "planning did not return a steps array" unless raw_steps.is_a?(Array)

        steps = raw_steps.map do |s|
          {title: s["title"], description: s["description"]}
        end

        Plan.new(steps: steps)
      end
    end
  end
end
