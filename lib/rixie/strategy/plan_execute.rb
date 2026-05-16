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

        plan.steps.each do |step|
          run = Run.new(
            user_input: task.user_input,
            agent: task.agent,
            context: task.context + completed_histories + [
              Context::Plan.new(steps: plan.steps, current_step: step)
            ]
          )
          task.runs << run
          run.execute(listener:)
          completed_histories << run.to_history if run.completed?
        end
      end

      def extract_plan(run)
        plan_call = run.find_tool_call("plan_done")

        raise AgentError, "plan_done tool call not found in run steps" if plan_call.nil?

        raw_steps = plan_call.arguments[:steps] || plan_call.arguments["steps"]
        if raw_steps.is_a?(String)
          begin
            raw_steps = JSON.parse(raw_steps)
          rescue JSON::ParserError => e
            raise AgentError, "plan_done returned invalid JSON for steps: #{e.message}"
          end
        end
        steps = raw_steps.map do |s|
          {title: s[:title] || s["title"], description: s[:description] || s["description"]}
        end

        Plan.new(steps: steps)
      end
    end
  end
end
