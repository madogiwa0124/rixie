# frozen_string_literal: true

require "json"

module Rixie
  module Subscribers
    class JsonLogger < Rixie::Subscriber
      def initialize(logger:)
        @logger = logger
      end

      def subscribe(listener)
        listener.on(Event::TaskStart) { |envelope|
          e = envelope.event
          emit(envelope, "task_start", user_input: e.user_input, strategy: e.strategy.class.name)
        }
        listener.on(Event::TaskEnd) { |envelope|
          emit(envelope, "task_end", status: envelope.event.status)
        }
        listener.on(Event::RunStart) { |envelope|
          emit(envelope, "run_start", user_input: envelope.event.user_input)
        }
        listener.on(Event::RunEnd) { |envelope|
          emit(envelope, "run_end", status: envelope.event.status)
        }
        listener.on(Event::CompressionStart) { |envelope|
          e = envelope.event
          emit(envelope, "compression_start", entry_count: e.entry_count, keep_recent: e.keep_recent)
        }
        listener.on(Event::CompressionEnd) { |envelope|
          e = envelope.event
          emit(envelope, "compression_end", status: e.status, entry_count: e.entry_count)
        }
        listener.on(Event::LlmCallStart) { |envelope|
          emit(envelope, "llm_call_start", step_count: envelope.event.step_count)
        }
        listener.on(Event::ToolCallStart) { |envelope|
          tc = envelope.event.tool_call
          emit(envelope, "tool_call_start", tool_call: {id: tc.id, name: tc.name, arguments: tc.arguments})
        }
        listener.on(Event::ToolCallEnd) { |envelope|
          tc = envelope.event.tool_call
          r = envelope.event.result
          emit(envelope, "tool_call_end",
            tool_call: {id: tc.id, name: tc.name},
            result: {content: r.content, error: r.error&.message})
        }
        listener.on(Event::Finished) { |envelope|
          emit(envelope, "finished", content: envelope.event.content)
        }
      end

      private

      def emit(envelope, type, **payload)
        record = {
          type: type,
          occurred_at: envelope.occurred_at.iso8601,
          session_id: envelope.session_id,
          task_id: envelope.task_id,
          run_id: envelope.run_id,
          seq: envelope.sequence_number,
          event_id: envelope.event_id,
          payload: payload
        }
        @logger.public_send(EventSeverity.for(envelope.event)) { JSON.generate(record) }
      end
    end
  end
end
