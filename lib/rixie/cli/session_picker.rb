# frozen_string_literal: true

require "reline"

module Rixie
  class CLI
    # Interactive picker for the -r / --resume flow. Lists saved sessions from
    # the store and reads the user's choice. Runs before the REPL starts; the
    # only class besides CLI allowed to read from stdin.
    class SessionPicker
      def initialize(store:, renderer:)
        @store = store
        @renderer = renderer
      end

      # Returns the chosen session_id, or nil to start a new session.
      def pick(limit: 20)
        sessions = @store.list_sessions(limit: limit)
        if sessions.empty?
          @renderer.text("No saved sessions found. Starting a new session.")
          return nil
        end

        @renderer.saved_sessions(sessions)
        read_selection(sessions)
      end

      private

      def read_selection(sessions)
        loop do
          raw = Reline.readline(@renderer.input_prompt("Resume session"), false)
          return nil if raw.nil?

          input = raw.strip
          return nil if input.empty?

          index = Integer(input, exception: false)
          return sessions[index - 1].session_id if index&.between?(1, sessions.size)

          @renderer.error("Please enter a number between 1 and #{sessions.size}.")
        end
      end
    end
  end
end
