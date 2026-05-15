# frozen_string_literal: true

module Rixie
  class Task
    attr_reader :user_input, :agent, :context, :strategy, :runs, :status, :output

    def initialize(user_input:, agent:, context:, strategy:, silent: false)
      @user_input = user_input
      @agent = agent
      @context = context
      @strategy = strategy
      @runs = []
      @status = "running"
      @output = nil
      @silent = silent
    end

    def execute(listener: nil)
      Rixie.logger.info { "[Task] started: #{@user_input.inspect}" } unless @silent
      listener ||= EventListener.new

      result = @strategy.run(task: self, listener:)
      @output = result
      @status = "completed"
      Rixie.logger.info { "[Task] completed" } unless @silent
    rescue => e
      @status = "failed"
      @output = e.message
      Rixie.logger.error { "[Task] failed: #{e.message}" } unless @silent
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
