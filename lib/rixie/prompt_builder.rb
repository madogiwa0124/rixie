# frozen_string_literal: true

module Rixie
  class PromptBuilder
    def build(user_input:, instructions:, context:)
      messages = []
      messages << {role: "system", content: instructions}
      messages.concat(context.flat_map(&:to_message))
      messages << {role: "user", content: user_input}
      messages
    end
  end
end
