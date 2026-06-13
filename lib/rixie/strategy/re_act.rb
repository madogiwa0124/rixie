# frozen_string_literal: true

module Rixie
  module Strategy
    class ReAct
      def run(task:, listener:)
        agent = Agent::ReAct.new(base_agent: task.agent)
        run = Run.new(user_input: task.user_input, agent: agent, context: task.context, schema: task.schema)
        task.runs << run
        run.execute(listener:)
        run.output
      end
    end
  end
end
