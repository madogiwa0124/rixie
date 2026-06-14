# frozen_string_literal: true

module Rixie
  module Subscribers
    class Logger < Rixie::Subscriber
      def initialize(logger:)
        @logger = logger
      end

      def subscribe(listener)
        listener.on(Event::TaskStart) { |envelope|
          e = envelope.event
          log(envelope) { "[Task] started: #{e.user_input.inspect} strategy=#{e.strategy.class.name} #{meta(envelope)}" }
        }
        listener.on(Event::TaskEnd) { |envelope|
          log(envelope) { "[Task] #{envelope.event.status} #{meta(envelope)}" }
        }
        listener.on(Event::RunStart) { |envelope|
          log(envelope) { "[Run] started: #{envelope.event.user_input.inspect} #{meta(envelope)}" }
        }
        listener.on(Event::RunEnd) { |envelope|
          log(envelope) { "[Run] #{envelope.event.status} #{meta(envelope)}" }
        }
        listener.on(Event::CompressionStart) { |envelope|
          e = envelope.event
          log(envelope) { "[Session] compression started: #{e.entry_count} entries (keep_recent: #{e.keep_recent}) #{meta(envelope)}" }
        }
        listener.on(Event::CompressionEnd) { |envelope|
          e = envelope.event
          msg = (e.status == "completed") ? "compression completed: #{e.entry_count} entries after" : "compression failed"
          log(envelope) { "[Session] #{msg} #{meta(envelope)}" }
        }
        listener.on(Event::LlmCallStart) { |envelope|
          e = envelope.event
          log(envelope) { "[Agent] llm_call model=#{e.model} provider=#{e.provider} #{meta(envelope)}" }
        }
        listener.on(Event::LlmCallEnd) { |envelope|
          e = envelope.event
          log(envelope) { "[Agent] llm_call_end input_tokens=#{e.usage[:input_tokens]} output_tokens=#{e.usage[:output_tokens]} finish_reason=#{e.finish_reason} #{meta(envelope)}" }
        }
        listener.on(Event::ToolCallStart) { |envelope|
          e = envelope.event
          log(envelope) { "[Agent] tool_call: #{e.tool_call.name}(#{e.tool_call.arguments}) #{meta(envelope)}" }
        }
        listener.on(Event::ToolCallEnd) { |envelope|
          log(envelope) { "[Agent] tool_result: #{envelope.event.result.content.inspect} #{meta(envelope)}" }
        }
        listener.on(Event::Finished) { |envelope|
          log(envelope) { "[Agent] finish: #{envelope.event.content.inspect} #{meta(envelope)}" }
        }
      end

      private

      def log(envelope, &block)
        @logger.public_send(EventSeverity.for(envelope.event), &block)
      end

      def meta(envelope)
        parts = []
        parts << "session_id=#{envelope.session_id}" if envelope.session_id
        parts << "task_id=#{envelope.task_id}" if envelope.task_id
        parts << "run_id=#{envelope.run_id}" if envelope.run_id
        parts << "seq=#{envelope.sequence_number}"
        parts << "event_id=#{envelope.event_id}"
        "[#{parts.join(" ")}]"
      end
    end
  end
end
