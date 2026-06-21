# frozen_string_literal: true

# CLI is not unit tested — use `bundle exec rixie` to test manually.

require "reline"
require "optparse"
require_relative "cli/instructions"
require_relative "cli/image_input"
require_relative "cli/path_completion"
require_relative "cli/terminal"
require_relative "cli/renderer"
require_relative "cli/session_picker"
require_relative "cli/tracing"
require_relative "cli/commands"

module Rixie
  class CLI
    attr_accessor :strategy_name
    attr_reader :current_model, :current_agent_name, :commands

    def current_context_size = session.context_size
    def current_context_length = session.context.size
    def compress!(keep_recent: 0) = session.compress!(keep_recent: keep_recent)

    # Framework-level configuration. The framework ships no opinionated
    # defaults — the reference app (bin/rixie) wires up tools and the system
    # prompt so that `Rixie::CLI.start` stays a blank slate for custom CLIs.
    class << self
      attr_accessor :default_instructions, :default_strategy
    end
    @default_instructions = nil
    @default_strategy = "simple"
    @extra_commands = []
    @extra_tools = []
    @extra_agents = {}

    def self.register_command(command_class)
      @extra_commands |= [command_class]
      self
    end

    def self.extra_commands
      @extra_commands
    end

    def self.reset_registered_commands!
      @extra_commands = []
    end

    def self.register_tool(tool)
      @extra_tools |= [tool]
      self
    end

    def self.extra_tools
      @extra_tools
    end

    def self.reset_registered_tools!
      @extra_tools = []
    end

    def self.register_agent(name, instructions: nil, tools: nil, model: nil)
      @extra_agents[name] = {instructions: instructions, tools: tools, model: model}.compact
      self
    end

    def self.extra_agents
      @extra_agents
    end

    def self.reset_registered_agents!
      @extra_agents = {}
    end

    def self.start(argv = ARGV)
      Terminal.enable_stdout_router
      new(argv).run
    end

    def initialize(argv)
      @options = {}

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: rixie [options]"

        opts.on("--provider PROVIDER", "LLM provider") do |v|
          @options[:provider] = v
        end

        opts.on("--model MODEL", "Model name") do |v|
          @options[:model] = v
        end

        opts.on("--instructions TEXT", "System instructions") do |v|
          @options[:instructions] = v
        end

        opts.on("-r", "--resume", "Resume a previous CLI session") do
          @options[:resume] = true
        end

        Tracing.add_options(opts, @options)

        opts.on("--debug", "Enable debug logging") do
          @options[:debug] = true
        end

        opts.on("--version", "Print version and exit") do
          puts Rixie::VERSION
          exit
        end

        opts.on("--help", "Print usage and exit") do
          puts opts
          exit
        end
      end

      parser.parse!(argv)
      @renderer = Renderer.new
      extra = self.class.extra_commands.map { |klass| klass.new(renderer: @renderer) }
      @commands = [
        Commands::Strategy.new(renderer: @renderer),
        Commands::Model.new(renderer: @renderer),
        Commands::Agent.new(renderer: @renderer),
        Commands::Context.new(renderer: @renderer),
        Commands::Compress.new(renderer: @renderer),
        Commands::Help.new(renderer: @renderer),
        *extra
      ]
      @command_map = @commands.each_with_object({}) { |cmd, h| h[cmd.name] = cmd }
    end

    def run
      if @options[:debug]
        Rixie.config.logger.reopen($stderr)
        Rixie.config.log_level = :debug
      else
        Rixie.config.logger.reopen(File::NULL)
      end

      provider = @options[:provider] || Rixie.config.default_provider
      model = @options[:model] || Rixie.config.default_model

      @tracing = Tracing.new(@options, renderer: renderer)

      renderer.welcome(version: Rixie::VERSION, provider: provider, model: model, tracing_endpoints: @tracing.active_endpoints)

      @current_model = @options[:model] || Rixie.config.default_model
      @current_agent_name = nil
      @current_agent_options = nil
      @session = @options[:resume] ? build_resumed_session : build_session
      @strategy_name = self.class.default_strategy
      setup_completion

      while (input = Reline.readline(renderer.prompt(@strategy_name), true))
        input = input.strip
        next if input.empty?
        break if input == "exit"

        if Reline::HISTORY.length > 1 && Reline::HISTORY[-2] == input
          Reline::HISTORY.pop
        end

        if input.start_with?("/")
          handle_command(input)
        else
          handle_input(input)
        end
      end

      renderer.goodbye
    rescue Interrupt
      renderer.goodbye
    end

    def switch_model(new_model)
      @current_model = new_model
      @session = build_session(context: @session.context, session_id: @session.session_id)
    end

    def switch_agent(name)
      agent_opts = self.class.extra_agents[name]
      @current_agent_name = name
      @current_agent_options = agent_opts
      @current_model = agent_opts[:model] || @current_model
      @session = build_session(context: @session.context, session_id: @session.session_id)
    end

    def current_strategy
      @command_map["strategy"].resolve(@strategy_name)
    end

    private

    attr_reader :session, :renderer

    def setup_completion
      slash_names = @commands.map { |cmd| "/#{cmd.name}" }
      Reline.completer_word_break_characters = ""

      Reline.completion_proc = ->(input) {
        if input.start_with?("/")
          name = input.delete_prefix("/").split(" ", 2).first
          cmd = @command_map[name]
          if cmd && input.include?(" ")
            cmd.complete(input)
          else
            slash_names.select { |c| c.start_with?(input) }
          end
        else
          PathCompletion.complete(input)
        end
      }
    end

    def handle_command(input)
      name, *args = input.delete_prefix("/").split(" ", 2)
      cmd = @command_map[name]

      if cmd
        cmd.call(args.first, cli: self)
      else
        renderer.unknown_command(name)
      end
    end

    def build_session(context: [], session_id: nil)
      Rixie::Session.new(initial_context: context, session_id: session_id, **session_options)
    end

    def build_resumed_session
      session_id = SessionPicker.new(store: cli_store, renderer: renderer).pick
      return build_session if session_id.nil?

      renderer.success("Resumed session #{session_id}")
      Rixie::Session.resume(session_id: session_id, **session_options)
    end

    def session_options
      {
        instructions: current_agent_instructions,
        tools: current_agent_tools,
        model: @current_model,
        provider: @options[:provider],
        store: cli_store,
        parallel_tool_calls: true,
        subscribers: @tracing.subscribers
      }
    end

    def current_agent_instructions
      @current_agent_options&.fetch(:instructions, nil) || @options[:instructions] || self.class.default_instructions
    end

    def current_agent_tools
      @current_agent_options&.key?(:tools) ? @current_agent_options[:tools] : self.class.extra_tools
    end

    def cli_store
      @cli_store ||= Rixie.config.store || Rixie::Store::File.new
    end

    def handle_input(input)
      content = ImageInput.parse(input)
      renderer.print_agent_prefix
      tool_section_started = false
      buffer = +""
      renderer.start_spinner

      session.live(content, strategy: current_strategy).each do |envelope|
        case envelope.event
        in Rixie::Event::Token[delta:]
          buffer << delta

        in Rixie::Event::ToolCallStart[tool_call:]
          renderer.stop_spinner
          unless buffer.empty?
            renderer.newline
            renderer.render_thought(buffer)
            buffer = +""
          end
          unless tool_section_started
            renderer.newline
            tool_section_started = true
          end
          renderer.render_tool_call_start(tool_call)

        in Rixie::Event::ToolCallEnd[tool_call:, result:]
          renderer.render_tool_call_end(tool_call, result)

        in Rixie::Event::ToolCallsCompleted
          renderer.print_agent_prefix
          renderer.start_spinner

        in Rixie::Event::ThoughtCompleted
          # finish thought — no action needed

        in Rixie::Event::Finished[content: nil]
          renderer.stop_spinner
          renderer.newline

        in Rixie::Event::Finished[content:]
          renderer.stop_spinner
          renderer.newline
          renderer.render_markdown(content)
          buffer = +""
        end
      end
    rescue Rixie::Error => e
      renderer.stop_spinner
      renderer.agent_error(e.message)
    rescue Interrupt
      renderer.stop_spinner
      renderer.agent_interrupted
    end
  end
end
