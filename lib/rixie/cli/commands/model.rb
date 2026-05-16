# frozen_string_literal: true

module Rixie
  class CLI
    module Commands
      class Model < Base
        def name = "model"

        def description = "Switch LLM model"

        def call(arg, cli:)
          if arg && !arg.empty?
            new_model = arg.strip
            return if new_model.empty?

            cli.switch_model(new_model)
            renderer.success("Model set to #{renderer.bold(new_model)}")
          else
            renderer.info("Current", cli.current_model)
          end
        end
      end
    end
  end
end
