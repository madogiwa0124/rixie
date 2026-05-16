# frozen_string_literal: true

module Rixie
  class CLI
    module Commands
      class Help < Base
        def name = "help"

        def description = "Show available commands"

        def call(_arg, cli:)
          renderer.heading("Commands:")
          cli.commands.each do |cmd|
            renderer.text("#{renderer.accent("/#{cmd.name}")}  — #{cmd.description}")
          end
          renderer.text("#{renderer.accent("exit")}  — Quit")
        end
      end
    end
  end
end
