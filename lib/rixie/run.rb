# frozen_string_literal: true

module Rixie
  class Run
    attr_reader :user_input, :agent, :context, :thoughts, :status, :output

    def initialize(user_input:, agent:, context:)
      @user_input = user_input
      @agent = agent
      @context = context
      @thoughts = []
      @status = "running"
      @output = nil
    end

    def execute(listener:)
      messages = PromptBuilder.new.build(
        user_input: user_input,
        instructions: agent.instructions,
        context: context
      )

      result = agent.think(messages:, listener:)
      @output = result.content
      @thoughts = result.thoughts
      @status = "completed"
    rescue
      @status = "failed"
      raise
    end

    def completed?
      @status == "completed"
    end

    def failed?
      @status == "failed"
    end

    def find_tool_call(name)
      thoughts.select(&:tool_call?).flat_map(&:tool_calls).find { it.name == name }
    end

    def to_history
      Context::History.new(input: user_input, thoughts: thoughts, output: output)
    end
  end
end
