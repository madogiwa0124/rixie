# frozen_string_literal: true

module Rixie
  class CLI
    class Tracing
      # Resolves the optional Langfuse subscriber from CLI options and
      # environment variables.
      class Langfuse
        def self.add_options(parser, options)
          parser.on("--langfuse [BASE_URL]", "Enable Langfuse tracing (default: http://localhost:3000)") do |v|
            options[:langfuse_url] = v || ENV.fetch("LANGFUSE_BASE_URL", "http://localhost:3000")
          end
        end

        attr_reader :subscriber

        def initialize(options, renderer:)
          @options = options
          @renderer = renderer
          @subscriber = resolve
        end

        def label = "Langfuse"

        # Display value for the welcome banner — nil when inactive.
        def endpoint
          @subscriber && @options[:langfuse_url]
        end

        private

        def resolve
          url = @options[:langfuse_url]
          return nil unless url

          pk = ENV["LANGFUSE_PUBLIC_KEY"]
          sk = ENV["LANGFUSE_SECRET_KEY"]
          unless pk && sk
            @renderer.error("Langfuse: set LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY to enable tracing")
            return nil
          end

          Rixie::Subscribers::Langfuse.new(base_url: url, public_key: pk, secret_key: sk)
        end
      end
    end
  end
end
