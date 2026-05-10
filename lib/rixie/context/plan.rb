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
          Execution plan:
          #{numbered}

          Current step: #{@current_step[:title]}
          #{@current_step[:description]}
        PROMPT
        [{role: "system", content: content}]
      end
    end
  end
end
