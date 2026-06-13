# frozen_string_literal: true

module Rixie
  class CLI
    module Commands
      class Agent < Base
        def name = "agent"

        def description = "Switch agent preset"

        def call(arg, cli:)
          agents = cli.class.extra_agents
          if agents.empty?
            renderer.text("No agents registered. Use #{renderer.bold("Rixie::CLI.register_agent")} to add one.")
            return
          end

          if arg && !arg.empty?
            set_agent(arg.strip, cli:)
          else
            renderer.info("Current", cli.current_agent_name || "default")
            renderer.heading("Available:")
            renderer.list(agents.keys, selected: cli.current_agent_name)
          end
        end

        def complete(input)
          arg = input.delete_prefix("/agent ")
          Rixie::CLI.extra_agents.keys.select { |a| a.start_with?(arg) }.map { |a| "/agent #{a}" }
        end

        private

        def set_agent(name, cli:)
          agents = cli.class.extra_agents
          if agents.key?(name)
            cli.switch_agent(name)
            renderer.success("Agent set to #{renderer.bold(name)}")
          else
            renderer.error("Unknown agent: #{name}")
            renderer.text("Available: #{agents.keys.join(", ")}")
          end
        end
      end
    end
  end
end
