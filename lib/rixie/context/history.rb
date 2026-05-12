# frozen_string_literal: true

module Rixie
  module Context
    class History
      def initialize(input:, steps:, output:)
        @input = input
        @steps = steps
        @output = output
      end

      def to_message
        messages = [Message::User.new(content: @input)]

        @steps.each do |step|
          tool_calls = step[:tool_calls]
          next if tool_calls.nil? || tool_calls.empty?

          messages << Message::Assistant.new(content: nil, tool_calls: tool_calls)
          step[:tool_results].each do |r|
            messages << Message::Tool.new(tool_call_id: r[:tool_call_id], content: r[:content])
          end
        end

        messages << Message::Assistant.new(content: @output, tool_calls: [])
        messages
      end

      def self.from_store(entry)
        new(
          input: entry["input"],
          steps: entry["steps"].map { |s|
            {
              tool_calls: s["tool_calls"].map { |tc|
                LLM::ToolCall.new(id: tc["id"], name: tc["name"], arguments: tc["arguments"])
              },
              tool_results: s["tool_results"].map { |r|
                {tool_call_id: r["tool_call_id"], content: r["content"]}
              }
            }
          },
          output: entry["output"]
        )
      end

      def to_store
        {
          "type" => "history",
          "input" => @input,
          "steps" => @steps.map { |s|
            {
              "tool_calls" => s[:tool_calls].map { |tc|
                {"id" => tc.id, "name" => tc.name, "arguments" => tc.arguments}
              },
              "tool_results" => s[:tool_results].map { |r|
                {"tool_call_id" => r[:tool_call_id], "content" => r[:content]}
              }
            }
          },
          "output" => @output
        }
      end
    end
  end
end
