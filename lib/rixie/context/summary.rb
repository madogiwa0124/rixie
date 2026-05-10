# frozen_string_literal: true

module Rixie
  module Context
    class Summary
      attr_reader :content

      def initialize(content:)
        @content = content
      end

      def to_message
        [{role: "system", content: "Previous conversation summary:\n#{@content}"}]
      end

      def to_store
        {"type" => "summary", "content" => @content}
      end
    end
  end
end
