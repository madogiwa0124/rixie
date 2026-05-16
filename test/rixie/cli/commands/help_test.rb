# frozen_string_literal: true

require_relative "../cli_test_helper"
require "rixie/cli/renderer"
require "rixie/cli/commands"

class CliCommandsHelpTest < Minitest::Test
  def setup
    super
    @renderer = Rixie::CLI::Renderer.new
    @command = Rixie::CLI::Commands::Help.new(renderer: @renderer)
  end

  def test_name
    assert_equal "help", @command.name
  end

  def test_description
    refute_empty @command.description
  end

  def test_call_does_not_raise
    strategy = Rixie::CLI::Commands::Strategy.new(renderer: @renderer)
    model = Rixie::CLI::Commands::Model.new(renderer: @renderer)
    cli = FakeCLI.new(commands: [strategy, model, @command])
    assert_output(/strategy/) { @command.call(nil, cli: cli) }
  end

  private

  FakeCLI = Struct.new(:commands, keyword_init: true)
end
