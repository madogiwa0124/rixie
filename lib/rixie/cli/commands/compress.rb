# frozen_string_literal: true

module Rixie
  class CLI
    module Commands
      class Compress < Base
        def name = "compress"

        def description = "Compress conversation context into a summary (optionally keep N recent entries)"

        def call(arg, cli:)
          keep_recent = parse_keep_recent(arg)
          return renderer.error("Invalid argument: expected a non-negative integer") if keep_recent.nil?

          if cli.current_context_length.zero?
            renderer.info("Context", "Already empty, nothing to compress")
            return
          end

          before_size = cli.current_context_size
          renderer.start_spinner
          cli.compress!(keep_recent: keep_recent)
          renderer.stop_spinner

          after_size = cli.current_context_size
          if after_size >= before_size
            renderer.info("Notice", "Compression did not reduce context size (~#{before_size} → ~#{after_size} tokens). Context may be too small to benefit from compression.")
          else
            renderer.success("Compressed ~#{before_size} → ~#{after_size} tokens")
          end
        rescue => e
          renderer.stop_spinner
          renderer.error(e.message)
        end

        private

        def parse_keep_recent(arg)
          return 0 if arg.nil? || arg.strip.empty?

          n = Integer(arg.strip)
          (n >= 0) ? n : nil
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
