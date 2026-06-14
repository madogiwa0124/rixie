# frozen_string_literal: true

module Rixie
  module Event
    LlmCallEnd = Data.define(:usage, :finish_reason)
  end
end
