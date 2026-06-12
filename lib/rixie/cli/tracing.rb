# frozen_string_literal: true

require_relative "tracing/langfuse"
require_relative "tracing/otel"

module Rixie
  class CLI
    # Facade over the optional tracing backends (Langfuse, Otel). cli.rb talks
    # only to this class; each backend owns its own OptionParser definitions,
    # environment variables, and subscriber construction.
    class Tracing
      BACKENDS = [Langfuse, Otel].freeze

      def self.add_options(parser, options)
        BACKENDS.each { |backend| backend.add_options(parser, options) }
      end

      def initialize(options, renderer:)
        @backends = BACKENDS.map { |backend| backend.new(options, renderer: renderer) }
      end

      # Subscribers to attach to the Session. Empty when tracing is disabled.
      def subscribers
        @backends.filter_map(&:subscriber)
      end

      # [label, endpoint] pairs for active backends — welcome banner display.
      def active_endpoints
        @backends.filter_map { |backend| backend.endpoint && [backend.label, backend.endpoint] }
      end
    end
  end
end
