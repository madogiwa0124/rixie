# frozen_string_literal: true

module Rixie
  module Event
    CompressionEnd = Data.define(:status, :entry_count)
  end
end
