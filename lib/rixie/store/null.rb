# frozen_string_literal: true

module Rixie
  module Store
    class Null < Base
      def save(session_id, context)
        # no-op
      end

      def load(session_id)
        []
      end

      def self.deserialize(entry)
        []
      end
    end
  end
end
