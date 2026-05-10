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

      # Serializes context for storage.
      # @param context [Array<Context::History, Context::Summary>]
      # @return [Array<Hash>]
      def serialize(context)
        raise Rixie::NotImplementedError, "#{self.class}#serialize is not implemented"
      end

      # Deserializes a single stored entry.
      # @param entry [Hash] with a "type" key ("summary" or "history")
      # @return [Context::History, Context::Summary]
      def self.deserialize(entry)
        raise Rixie::NotImplementedError, "#{self}.deserialize is not implemented"
      end
    end
  end
end
