# frozen_string_literal: true

module Rixie
  module Context
    class Summary
      attr_reader :content

      def initialize(content:)
        @content = content
      end

      def self.from_store(entry)
        new(content: entry["content"])
      end

      def to_message
        [Message::System.new(content: "Previous conversation summary:\n#{@content}")]
      end

      def to_store
        {"type" => "summary", "content" => @content}
      end
    end
  end
end
