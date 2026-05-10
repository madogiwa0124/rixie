# frozen_string_literal: true

module Rixie
  class EventListener
    def initialize
      @subscribers = Hash.new { |h, k| h[k] = [] }
    end

    def on(event, &block)
      @subscribers[event] << block
      self
    end

    def emit(event, payload = {})
      @subscribers[event].each { |block| block.call(payload) }
    end
  end
end
