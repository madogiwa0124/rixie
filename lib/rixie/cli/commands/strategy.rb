# frozen_string_literal: true

module Rixie
  class CLI
    module Commands
      class Strategy < Base
        STRATEGIES = {
          "simple" => Rixie::Strategy::Simple,
          "plan-execute" => Rixie::Strategy::PlanExecute
        }.freeze

        def name = "strategy"

        def description = "Switch execution strategy"

        def call(arg, cli:)
          if arg && !arg.empty?
            set_strategy(arg.strip, cli:)
          else
            renderer.info("Current", cli.strategy_name)
            renderer.heading("Available:")
            renderer.list(STRATEGIES.keys, selected: cli.strategy_name)
          end
        end

        def complete(input)
          arg = input.delete_prefix("/strategy ")
          STRATEGIES.keys.select { |s| s.start_with?(arg) }.map { |s| "/strategy #{s}" }
        end

        def resolve(name)
          STRATEGIES[name]&.new
        end

        private

        def set_strategy(name, cli:)
          if STRATEGIES.key?(name)
            cli.strategy_name = name
            renderer.success("Strategy set to #{renderer.bold(name)}")
          else
            renderer.error("Unknown strategy: #{name}")
            renderer.text("Available: #{STRATEGIES.keys.join(", ")}")
          end
        end
      end
    end
  end
end
