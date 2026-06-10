# frozen_string_literal: true

module Rixie
  module Subscribers
    # Maps an Event::* instance to the log severity (:debug, :info, :warn)
    # at which subscribers should emit it. Shared by Subscribers::Logger and
    # Subscribers::JsonLogger so the mapping does not drift between them.
    module EventSeverity
      def self.for(event)
        case event
        when Event::LlmCallStart, Event::LlmCallEnd, Event::ToolCallStart
          :debug
        when Event::ToolCallEnd
          event.result.error? ? :warn : :debug
        when Event::CompressionEnd
          (event.status == "completed") ? :info : :warn
        else
          :info
        end
      end
    end
  end
end
