# frozen_string_literal: true

module Rixie
  class EventListener
    def initialize
      @listeners = Hash.new { |h, k| h[k] = [] }
    end

    def on(event_class, &block)
      @listeners[event_class] << block
      self
    end

    def emit(event)
      @listeners[event.class].each { |block| block.call(event) }
    end
  end
end
