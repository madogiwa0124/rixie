# frozen_string_literal: true

module Rixie
  module Event
    ToolCallsCompleted = Data.define(:tool_calls, :tool_results)
  end
end
