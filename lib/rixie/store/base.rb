# frozen_string_literal: true

module Rixie
  module Store
    # Interface definition for storage adapters.
    # Subclasses must implement #save and #load.
    class Base
      # Persists context for the given session_id.
      # @param session_id [String]
      # @param context [Array]
      def save(session_id, context)
        raise Rixie::NotImplementedError, "#{self.class}#save is not implemented"
      end

      # Retrieves context for the given session_id.
      # @param session_id [String]
      # @return [Array]
      def load(session_id)
        raise Rixie::NotImplementedError, "#{self.class}#load is not implemented"
      end

      # Lists resumable sessions for UI use.
      # @param limit [Integer, nil]
      # @return [Array<Row>]
      def list_sessions(limit: nil)
        raise Rixie::NotImplementedError, "#{self.class}#list_sessions is not implemented"
      end

      # Serializes context for storage.
      # @param context [Array<Context::History, Context::Summary>]
      # @return [Array<Hash>]
      def serialize(context)
        raise Rixie::NotImplementedError, "#{self.class}#serialize is not implemented"
      end

      # Deserializes a single stored entry (the `to_store` hash format).
      # @param entry [Hash] with a "type" key ("summary" or "history")
      # @return [Context::History, Context::Summary]
      def self.deserialize(entry)
        case entry["type"]
        when "summary" then Context::Summary.from_store(entry)
        when "history" then Context::History.from_store(entry)
        else raise Rixie::Error, "Unknown context entry type: #{entry["type"]}"
        end
      end

      private

      # Shared helpers for building #list_sessions rows from stored entry hashes.

      def latest_first(rows, limit:)
        sorted = rows.sort_by { |row| row.updated_at || "" }.reverse
        limit ? sorted.first(limit) : sorted
      end

      def preview_from(entries)
        history = entries.reverse_each.find { it["type"] == "history" }
        return "(no messages)" if history.nil?

        input = history["input"].to_s.strip
        return "(empty message)" if input.empty?

        (input.length > 80) ? "#{input[0, 80]}..." : input
      end
    end
  end
end
