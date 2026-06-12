# frozen_string_literal: true

module Rixie
  class PromptBuilder
    def build(user_input:, instructions:, context:)
      messages = []
      messages << Message::System.new(content: instructions) unless instructions.nil? || instructions.empty?
      messages.concat(context.flat_map(&:to_message))
      messages << Message::User.new(content: user_input)
      messages
    end
  end
end
