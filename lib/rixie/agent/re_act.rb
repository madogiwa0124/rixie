# frozen_string_literal: true

module Rixie
  class Agent
    class ReAct
      DEFAULT_REACT_INSTRUCTIONS = <<~INSTRUCTIONS
        You are operating in ReAct (Reasoning + Acting) mode.

        For every step that requires a tool, FIRST output your reasoning as plain text BEFORE making the tool call. Format your reasoning as:

        Thought: <one or two sentences explaining what you need to do next and why>

        Then make exactly ONE tool call. Do not call multiple tools at once.

        After the tool returns (an Observation), produce another Thought before the next Action, or provide the final answer if you have enough information to respond.

        The reasoning trace is essential — always include a Thought before each Action.
      INSTRUCTIONS

      def initialize(base_agent:, react_instructions: DEFAULT_REACT_INSTRUCTIONS)
        @base_agent = base_agent
        @react_instructions = react_instructions
      end

      def instructions
        [@base_agent.instructions, @react_instructions].compact.reject(&:empty?).join("\n\n")
      end

      def tools
        @base_agent.tools
      end

      def llm_client
        @base_agent.llm_client
      end

      def think(messages:, listener:)
        internal_agent.think(messages:, listener:)
      end

      private

      def internal_agent
        @internal_agent ||= Agent.new(
          instructions: instructions,
          tools: tools,
          llm_client: @base_agent.llm_client,
          max_steps: @base_agent.max_steps,
          token_counter: @base_agent.token_counter,
          # Intentionally NOT inherited: ReAct requires one tool call per iteration.
          parallel_tool_calls: false
        )
      end
    end
  end
end
