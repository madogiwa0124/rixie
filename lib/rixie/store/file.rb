# frozen_string_literal: true

require "json"
require "time"
require "tempfile"
require "fileutils"

module Rixie
  module Store
    class File < Base
      DEFAULT_PATH = ::File.join(Dir.home, ".rixie", "sessions.json")

      def initialize(path: DEFAULT_PATH)
        @path = path
      end

      def save(session_id, context)
        with_store do |data|
          data["sessions"] ||= {}
          current = data["sessions"][session_id] || {}
          created_at = current["created_at"] || Time.now.utc.iso8601

          data["sessions"][session_id] = {
            "created_at" => created_at,
            "updated_at" => Time.now.utc.iso8601,
            "entries" => context.map(&:to_store)
          }
        end
      end

      def load(session_id)
        session = read_store.dig("sessions", session_id)
        return [] if session.nil?

        entries = session.fetch("entries", [])
        entries.map { |entry| self.class.deserialize(entry) }
      end

      def list_sessions(limit: nil)
        sessions = read_store.fetch("sessions", {})

        rows = sessions.map do |session_id, payload|
          entries = payload.fetch("entries", [])
          Row.new(
            session_id: session_id,
            created_at: payload["created_at"],
            updated_at: payload["updated_at"],
            entry_count: entries.size,
            preview: preview_from(entries)
          )
        end

        latest_first(rows, limit: limit)
      end

      private

      def with_store
        data = read_store
        yield data
        write_store(data)
      end

      def read_store
        return {"sessions" => {}} unless ::File.exist?(@path)

        raw = ::File.read(@path)
        return {"sessions" => {}} if raw.strip.empty?

        parsed = JSON.parse(raw)
        parsed.is_a?(Hash) ? parsed : {"sessions" => {}}
      rescue JSON::ParserError
        raise Rixie::Error, "Invalid JSON store file: #{@path}"
      end

      def write_store(data)
        dir = ::File.dirname(@path)
        FileUtils.mkdir_p(dir)

        Tempfile.create("rixie-store", dir) do |tmp|
          tmp.write(JSON.pretty_generate(data))
          tmp.flush
          tmp.fsync
          ::File.rename(tmp.path, @path)
        end
      end
    end
  end
end
