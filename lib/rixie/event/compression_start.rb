# frozen_string_literal: true

module Rixie
  module Event
    CompressionStart = Data.define(:entry_count, :keep_recent)
  end
end
