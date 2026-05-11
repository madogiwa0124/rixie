# frozen_string_literal: true

module Rixie
  module Event
    StepCompleted = Data.define(:tool_calls, :tool_results)
  end
end
