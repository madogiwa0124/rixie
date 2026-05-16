# frozen_string_literal: true

module Rixie
  class Agent
    class Plan
      PLAN_DONE_TOOL = Rixie::Tool.new(
        name: "plan_done",
        description: "Call this tool when the plan is complete.",
        input_schema: {
          type: "object",
          properties: {
            steps: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  title: {type: "string"},
                  description: {type: "string"}
                },
                required: ["title", "description"]
              }
            }
          },
          required: ["steps"]
        },
        call: ->(_args) { "Planning complete." },
        return_direct: true
      )

      DEFAULT_PLANNING_INSTRUCTIONS = <<~INSTRUCTIONS
        Make a plan to accomplish the given task. Do not output any text — call plan_done directly with the plan steps.
      INSTRUCTIONS

      def initialize(base_agent:, planning_instructions: DEFAULT_PLANNING_INSTRUCTIONS)
        @base_agent = base_agent
        @planning_instructions = planning_instructions
      end

      def instructions
        [@base_agent.instructions, @planning_instructions].join("\n\n")
      end

      def tools
        @base_agent.tools + [PLAN_DONE_TOOL]
      end

      def think(messages:, listener:)
        internal_agent.think(messages:, listener:)
      end

      private

      def internal_agent
        @internal_agent ||= Agent.new(
          instructions: instructions,
          tools: tools,
          llm_client: @base_agent.llm_client
        )
      end
    end
  end
end
