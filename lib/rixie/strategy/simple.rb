# frozen_string_literal: true

module Rixie
  module Strategy
    class Simple
      def run(task:, listener:)
        run = Run.new(user_input: task.user_input, agent: task.agent, context: task.context)
        task.runs << run
        run.execute(listener:)
        run.output
      end
    end
  end
end
