# frozen_string_literal: true

module Rixie
  class Task
    attr_reader :user_input, :agent, :context, :strategy, :runs, :status, :output

    def initialize(user_input:, agent:, context:, strategy:)
      @user_input = user_input
      @agent = agent
      @context = context
      @strategy = strategy
      @runs = []
      @status = "running"
      @output = nil
    end

    def execute
      listener = EventListener.new
      listener.on(:step_completed) { |e| runs.last.add_step(**e) }

      result = @strategy.run(task: self, listener:)
      @output = result
      @status = "completed"
    rescue => e
      @status = "failed"
      @output = e.message
      raise
    end

    def completed?
      @status == "completed"
    end

    def failed?
      @status == "failed"
    end

    def to_history
      @runs.select(&:completed?).map(&:to_history)
    end
  end
end
