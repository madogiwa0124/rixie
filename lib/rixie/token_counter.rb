# frozen_string_literal: true

module Rixie
  module TokenCounter
    # Approximate token count using character length (1 token ≈ 4 characters).
    # Replace via Session.new(token_counter: your_callable)
    # to use an exact counter such as tiktoken.
    DEFAULT = ->(messages) { messages.sum { |m| m.content.to_s.length } / 4 }
  end
end
