# frozen_string_literal: true

module Rixie
  module Context
    class Plan
      def initialize(steps:, current_step:)
        @steps = steps
        @current_step = current_step
      end

      def to_message
        numbered = @steps.each_with_index.map { |s, i| "#{i + 1}. #{s[:title]}" }.join("\n")
        content = <<~PROMPT
          You are executing one step of a multi-step plan. Your output for this step will be combined with the outputs of other steps into a single response.

          Full plan:
          #{numbered}

          Current step: #{@current_step[:title]}
          #{@current_step[:description]}

          Output instructions:
          - Produce only the content for this step. Do not summarize other steps.
          - Do not add closing remarks, transition sentences, or offers to elaborate (e.g. "Feel free to ask if you want more details").
          - Write as if the reader will continue reading the next step's output immediately after.
        PROMPT
        [Message::System.new(content: content)]
      end
    end
  end
end
