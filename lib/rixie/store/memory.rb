# frozen_string_literal: true

module Rixie
  module Store
    class Memory < Base
      def initialize
        @data = {}
      end

      def save(session_id, context)
        @data[session_id] = context.map(&:to_store)
      end

      def load(session_id)
        entries = @data.fetch(session_id, nil)
        return [] if entries.nil?

        entries.map { |entry| self.class.deserialize(entry) }
      end

      def self.deserialize(entry)
        case entry["type"]
        when "summary" then Context::Summary.from_store(entry)
        when "history" then Context::History.from_store(entry)
        else raise Rixie::Error, "Unknown context entry type: #{entry["type"]}"
        end
      end
    end
  end
end
