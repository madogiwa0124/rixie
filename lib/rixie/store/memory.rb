# frozen_string_literal: true

module Rixie
  module Store
    class Memory < Base
      def initialize
        @data = {}
        @updated_at = {}
      end

      def save(session_id, context)
        @data[session_id] = context.map(&:to_store)
        @updated_at[session_id] = Time.now.utc.iso8601
      end

      def load(session_id)
        entries = @data.fetch(session_id, nil)
        return [] if entries.nil?

        entries.map { |entry| self.class.deserialize(entry) }
      end

      def list_sessions(limit: nil)
        rows = @data.map do |session_id, entries|
          Row.new(
            session_id: session_id,
            created_at: nil,
            updated_at: @updated_at[session_id],
            entry_count: entries.size,
            preview: preview_from(entries)
          )
        end

        latest_first(rows, limit: limit)
      end
    end
  end
end
