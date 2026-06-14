# frozen_string_literal: true

module Rixie
  module Event
    LlmCallStart = Data.define(:model, :provider)
  end
end
