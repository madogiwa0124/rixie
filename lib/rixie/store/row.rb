# frozen_string_literal: true

module Rixie
  module Store
    # One row returned by a store's #list_sessions.
    # Shared by all store adapters — custom stores should return these
    # so UIs (e.g. the CLI resume picker) can rely on the shape.
    Row = Data.define(:session_id, :created_at, :updated_at, :entry_count, :preview)
  end
end
