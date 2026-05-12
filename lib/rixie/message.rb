# frozen_string_literal: true

module Rixie
  module Message
    System    = Data.define(:content)
    User      = Data.define(:content)
    Assistant = Data.define(:content, :tool_calls)
    Tool      = Data.define(:tool_call_id, :content)
  end
end
