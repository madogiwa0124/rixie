# frozen_string_literal: true

module Rixie
  class PromptBuilder
    def build(user_input:, instructions:, context:, steps:)
      messages = []
      messages << {role: "system", content: instructions}
      messages.concat(context.flat_map(&:to_message))
      messages.concat(steps_messages(steps))
      messages << {role: "user", content: user_input}
      messages
    end

    private

    def steps_messages(steps)
      steps.flat_map do |step|
        tool_calls = step[:tool_calls]
        next [] if tool_calls.nil? || tool_calls.empty?

        assistant = {role: "assistant", content: nil, tool_calls: tool_calls.map(&:to_llm_format)}
        tool_results = step[:tool_results].map do |r|
          {role: "tool", tool_call_id: r[:tool_call_id], content: r[:content]}
        end
        [assistant, *tool_results]
      end
    end
  end
end
