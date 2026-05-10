# frozen_string_literal: true

module Rixie
  module Store
    class Memory < Base
      def initialize
        @data = {}
      end

      def save(session_id, context)
        @data[session_id] = context
      end

      def load(session_id)
        @data.fetch(session_id, [])
      end
    end
  end
end
