# frozen_string_literal: true

module Rixie
  module Event
    ToolCallEnd = Data.define(:tool_call, :result)
  end
end
