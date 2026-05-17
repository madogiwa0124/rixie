# frozen_string_literal: true

require "securerandom"

module Rixie
  class EventListener
    def initialize(session_id: nil, task_id: nil)
      @session_id = session_id
      @task_id = task_id
      @run_id = nil
      @sequence_number = 0
      @listeners = Hash.new { |h, k| h[k] = [] }
    end

    attr_writer :run_id

    def on(event_class, &block)
      @listeners[event_class] << block
      self
    end

    def emit(event)
      @sequence_number += 1
      envelope = Event::Envelope.new(
        event: event,
        occurred_at: Time.now,
        session_id: @session_id,
        task_id: @task_id,
        run_id: @run_id,
        sequence_number: @sequence_number,
        event_id: SecureRandom.uuid
      )
      @listeners[event.class].each { |block| block.call(envelope) }
    end
  end
end
