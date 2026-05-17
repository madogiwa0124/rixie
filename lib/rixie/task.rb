# frozen_string_literal: true

require "securerandom"

module Rixie
  class Task
    attr_reader :id, :user_input, :agent, :context, :strategy, :runs, :status, :output

    def initialize(user_input:, agent:, context:, strategy:, subscribers: [], session_id: nil)
      @id = SecureRandom.uuid
      @session_id = session_id
      @user_input = user_input
      @agent = agent
      @context = context
      @strategy = strategy
      @subscribers = subscribers
      @runs = []
      @status = "running"
      @output = nil
    end

    def execute
      listener = EventListener.new(session_id: @session_id, task_id: @id)
      listener.on(Event::ToolCallsCompleted) { |envelope|
        e = envelope.event
        runs.last.add_step(tool_calls: e.tool_calls, tool_results: e.tool_results)
      }
      @subscribers.each { |s| s.subscribe(listener) }
      listener.emit(Event::TaskStart.new(user_input: @user_input, strategy: @strategy))

      result = @strategy.run(task: self, listener:)
      @output = result
      @status = "completed"
      listener.emit(Event::TaskEnd.new(output: @output, status: @status))
    rescue
      @status = "failed"
      listener&.emit(Event::TaskEnd.new(output: nil, status: @status))
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
