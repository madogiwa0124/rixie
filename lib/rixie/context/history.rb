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
        messages = [{role: "user", content: @input}]

        @steps.each do |step|
          tool_calls = step[:tool_calls]
          next if tool_calls.nil? || tool_calls.empty?

          messages << {role: "assistant", content: nil, tool_calls: tool_calls.map(&:to_llm_format)}
          step[:tool_results].each do |r|
            messages << {role: "tool", tool_call_id: r[:tool_call_id], content: r[:content]}
          end
        end

        messages << {role: "assistant", content: @output}
        messages
      end
    end
  end
end
