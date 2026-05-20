# frozen_string_literal: true

module Rixie
  class CLI
    module Commands
      class Context < Base
        def name = "context"

        def description = "Show current context size"

        def call(_arg, cli:)
          renderer.info("Context size", "~#{cli.current_context_size} tokens")
          renderer.info("Entries", cli.current_context_length.to_s)
        end
      end
    end
  end
end
