# frozen_string_literal: true

module Rixie
  class Agent
    class Compressor
      DEFAULT_SUMMARIZATION_INSTRUCTIONS = <<~INSTRUCTIONS
        You are a conversation summarizer.
        Summarize the following conversation history concisely,
        preserving key facts, decisions, and context needed
        for future interactions. Do not add commentary.
      INSTRUCTIONS

      def initialize(base_agent:, summarization_instructions: DEFAULT_SUMMARIZATION_INSTRUCTIONS)
        @base_agent = base_agent
        @summarization_instructions = summarization_instructions
      end

      def instructions
        @summarization_instructions
      end

      def tools
        []
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
