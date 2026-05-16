# frozen_string_literal: true

require_relative "terminal"
require_relative "spinner"

module Rixie
  class CLI
    class Renderer
      def initialize(terminal: Terminal.new)
        @terminal = terminal
        @spinner = Spinner.new(terminal: @terminal, prefix: agent_prefix)
      end

      # -- General output --

      def success(message)
        puts_indented("#{@terminal.success("✓")} #{message}")
      end

      def error(message)
        puts_indented(@terminal.error(message))
      end

      def info(label, value)
        puts_indented("#{@terminal.bold("#{label}:")} #{value}")
      end

      def heading(text)
        puts_indented(@terminal.bold(text))
      end

      def list(items, selected: nil)
        items.each_with_index do |item, i|
          marker = (item == selected) ? " #{@terminal.success("✓")}" : ""
          puts_indented("#{@terminal.accent("#{i + 1}.")} #{item}#{marker}", level: 2)
        end
      end

      def text(message)
        puts_indented(message)
      end

      def welcome(version:, provider:, model:)
        frame("Rixie v#{version}", color: :red) do
          info("Provider", provider)
          info("Model", model)
          text("Type #{@terminal.warn("exit")} or press #{@terminal.warn("Ctrl+C")} to quit.")
        end
      end

      def goodbye
        newline
        puts @terminal.success("Goodbye!")
      end

      def unknown_command(name)
        puts "#{@terminal.error("Unknown command:")} /#{name}"
      end

      def agent_error(message)
        newline
        puts "#{@terminal.error("Error:")} #{message}"
      end

      def agent_interrupted
        newline
        puts @terminal.warn("Interrupted.")
      end

      def newline
        puts "\n"
      end

      def prompt(strategy_name)
        if strategy_name == "simple"
          "#{@terminal.accent(">")} "
        else
          "#{@terminal.accent(">")} #{@terminal.secondary("(#{strategy_name})")} "
        end
      end

      def bold(text) = @terminal.bold(text)

      def accent(text) = @terminal.accent(text)

      def input_prompt(label)
        "  #{@terminal.bold("#{label}:")} "
      end

      def stream_token(delta)
        print delta
        $stdout.flush
      end

      # -- Agent output --

      def agent_prefix
        "#{@terminal.bold("Agent:")} "
      end

      def print_agent_prefix
        print agent_prefix
      end

      def render_tool_call(thought)
        thought.tool_calls.each_with_index do |tc, i|
          result = thought.tool_results[i]
          frame(fmt("{{*}} Tool: #{@terminal.bold(tc.name)}"), color: :cyan) do
            format_tool_args(tc.arguments).each { |line| puts line }
            puts_indented("#{@terminal.bold("Result:")} #{result[:content].to_s.lines.first&.chomp}")
          end
        end
      end

      # -- Spinner --

      def start_spinner = @spinner.start

      def stop_spinner = @spinner.stop

      private

      def fmt(text) = @terminal.fmt(text)

      def frame(title, **opts, &block) = @terminal.frame(title, **opts, &block)

      def indented(text, level: 1) = "#{"  " * level}#{text}"

      def puts_indented(text, level: 1) = puts indented(text, level: level)

      def format_tool_args(arguments)
        return [] if arguments.nil? || arguments.empty?

        arguments.flat_map do |key, value|
          label = indented(@terminal.bold("#{key}:"))
          if value.is_a?(Array)
            items = value.each_with_index.map do |item, i|
              summary = item.is_a?(Hash) ? item.map { |k, v| "#{k}: #{v}" }.join(", ") : item.to_s
              indented("#{@terminal.accent("#{i + 1}.")} #{summary}", level: 2)
            end
            [label, *items]
          else
            ["#{label} #{value}"]
          end
        end
      end
    end
  end
end
