# frozen_string_literal: true

module Rixie
  module Context
    class History
      def initialize(input:, thoughts:, output:)
        @input = input
        @thoughts = thoughts
        @output = output
      end

      def to_message
        messages = [Message::User.new(content: @input)]

        @thoughts.each do |thought|
          next unless thought.tool_call?
          next if thought.tool_calls.nil? || thought.tool_calls.empty?

          messages << Message::Assistant.new(content: thought.content, tool_calls: thought.tool_calls)
          thought.tool_results.each do |r|
            messages << Message::Tool.new(tool_call_id: r.tool_call_id, content: r.content)
          end
        end

        messages << Message::Assistant.new(content: @output, tool_calls: [])
        messages
      end

      def self.from_store(entry)
        thoughts = (entry["thoughts"] || []).map { |t|
          tool_calls = t["tool_calls"].map { |tc|
            LLM::ToolCall.new(id: tc["id"], name: tc["name"], arguments: tc["arguments"])
          }
          tool_results = t["tool_results"].map { |r|
            ToolExecutor::Result.new(tool_call_id: r["tool_call_id"], content: r["content"], error: nil)
          }
          Agent::Thought.new(type: :tool_call, content: t["content"], tool_calls: tool_calls, tool_results: tool_results)
        }
        new(input: entry["input"], thoughts: thoughts, output: entry["output"])
      end

      def to_store
        {
          "type" => "history",
          "input" => @input,
          "thoughts" => @thoughts.select(&:tool_call?).map { |t|
            {
              "content" => t.content,
              "tool_calls" => t.tool_calls.map { |tc|
                {"id" => tc.id, "name" => tc.name, "arguments" => tc.arguments}
              },
              "tool_results" => t.tool_results.map { |r|
                {"tool_call_id" => r.tool_call_id, "content" => r.content}
              }
            }
          },
          "output" => @output
        }
      end
    end
  end
end
