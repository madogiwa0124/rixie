# frozen_string_literal: true

module Rixie
  class Run
    attr_reader :user_input, :agent, :context, :steps, :status, :output

    def initialize(user_input:, agent:, context:)
      @user_input = user_input
      @agent = agent
      @context = context
      @steps = []
      @status = "running"
      @output = nil
    end

    def execute(listener:)
      messages = PromptBuilder.new.build(
        user_input: user_input,
        instructions: agent.instructions,
        context: context
      )

      @output = agent.think(messages:, listener:)
      @status = "completed"
    rescue
      @status = "failed"
      raise
    end

    def add_step(tool_calls:, tool_results:)
      @steps << {tool_calls: tool_calls, tool_results: tool_results}
    end

    def completed?
      @status == "completed"
    end

    def failed?
      @status == "failed"
    end

    def find_tool_call(name)
      steps.flat_map { |s| s[:tool_calls] }.find { |tc| tc.name == name }
    end

    def to_history
      Context::History.new(input: user_input, steps: steps, output: output)
    end
  end
end
