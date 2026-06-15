# frozen_string_literal: true

module Rixie
  class Agent
    # The planning half of `Strategy::PlanExecute`. Wraps a base agent and asks
    # the model to return a step-by-step plan as **structured output** (a JSON
    # object matching `PLAN_SCHEMA`) — not via a tool call. Planning is decomposition,
    # not action: the plan phase exposes no tools, so the model cannot start executing
    # the task, and structured output (with its corrective retry) reliably coerces a
    # conforming plan even from weaker models.
    class Plan
      PLAN_SCHEMA = {
        "type" => "object",
        "properties" => {
          "steps" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "properties" => {
                "title" => {"type" => "string"},
                "description" => {"type" => "string"}
              },
              "required" => ["title", "description"]
            }
          }
        },
        "required" => ["steps"]
      }.freeze

      DEFAULT_PLANNING_INSTRUCTIONS = <<~INSTRUCTIONS
        Break the task into a short, ordered list of concrete steps to accomplish it.
        Respond with a JSON object containing a "steps" array; each step has a "title"
        and a "description". Plan the work only — do not perform the task.
      INSTRUCTIONS

      def initialize(base_agent:, planning_instructions: DEFAULT_PLANNING_INSTRUCTIONS)
        @base_agent = base_agent
        @planning_instructions = planning_instructions
      end

      def instructions
        [@base_agent.instructions, @planning_instructions, available_tools_note].compact.reject(&:empty?).join("\n\n")
      end

      def tools
        []
      end

      # Always plans with `PLAN_SCHEMA` — the result is a Hash, not a tool call.
      def think(messages:, listener:, schema: nil)
        internal_agent.think(messages:, listener:, schema: PLAN_SCHEMA)
      end

      private

      # Lists the execution-phase tools (name + description) so the planner can plan
      # steps around them — e.g. a "get the current date" step using `current_time`.
      # Safe to name them here: the plan phase runs with no tools and a forced schema,
      # so the model produces the steps JSON and cannot emit (hallucinate) tool calls.
      def available_tools_note
        return nil if @base_agent.tools.empty?

        listing = @base_agent.tools.map { |tool| "- #{tool.name}: #{tool.description}" }.join("\n")
        "The execution phase can use these tools; include steps that use them when helpful:\n#{listing}"
      end

      def internal_agent
        @internal_agent ||= Agent.new(
          instructions: instructions,
          tools: [],
          llm_client: @base_agent.llm_client,
          max_steps: @base_agent.max_steps,
          token_counter: @base_agent.token_counter
        )
      end
    end
  end
end
