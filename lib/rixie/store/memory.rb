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
        when "summary"
          Context::Summary.new(content: entry["content"])
        when "history"
          Context::History.new(
            input: entry["input"],
            steps: entry["steps"].map { |s|
              {
                tool_calls: s["tool_calls"].map { |tc|
                  Agent::ToolCall.new(
                    id: tc["id"],
                    name: tc.dig("function", "name"),
                    arguments: JSON.parse(tc.dig("function", "arguments") || "{}")
                  )
                },
                tool_results: s["tool_results"].map { |r|
                  {tool_call_id: r["tool_call_id"], content: r["content"]}
                }
              }
            },
            output: entry["output"]
          )
        else
          raise Rixie::Error, "Unknown context entry type: #{entry["type"]}"
        end
      end
    end
  end
end
