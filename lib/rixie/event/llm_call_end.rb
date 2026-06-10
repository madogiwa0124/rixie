# frozen_string_literal: true

module Rixie
  module Event
    LlmCallEnd = Data.define(:step_count, :usage, :finish_reason)
  end
end
