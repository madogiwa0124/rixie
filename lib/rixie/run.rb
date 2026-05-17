# frozen_string_literal: true

require "securerandom"

module Rixie
  class Run
    attr_reader :id, :user_input, :agent, :context, :thoughts, :steps, :status, :output

    def initialize(user_input:, agent:, context:)
      @id = SecureRandom.uuid
      @user_input = user_input
      @agent = agent
      @context = context
      @thoughts = []
      @steps = []
      @status = "running"
      @output = nil
    end

    def execute(listener:)
      listener.run_id = @id
      listener.emit(Event::RunStart.new(user_input: user_input))
      messages = PromptBuilder.new.build(
        user_input: user_input,
        instructions: agent.instructions,
        context: context
      )

      result = agent.think(messages:, listener:)
      @output = result.content
      @thoughts = result.thoughts
      @status = "completed"
      listener.emit(Event::RunEnd.new(output: @output, status: @status))
    rescue
      @status = "failed"
      listener.emit(Event::RunEnd.new(output: nil, status: @status))
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
      thoughts.select(&:tool_call?).flat_map(&:tool_calls).find { it.name == name }
    end

    def to_history
      Context::History.new(input: user_input, thoughts: thoughts, output: output)
    end
  end
end
