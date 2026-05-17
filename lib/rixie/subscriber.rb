# frozen_string_literal: true

module Rixie
  class Subscriber
    # Registers event handlers on the given listener.
    # Called once per Task execution (new EventListener each time).
    # Implement by calling listener.on(EventClass) { |e| ... } for each event of interest.
    def subscribe(listener)
      raise NotImplementedError, "#{self.class}#subscribe must be implemented"
    end
  end
end
