# frozen_string_literal: true

require_relative "../cli_test_helper"
require "rixie/cli/renderer"
require "rixie/cli/commands"

class CliCommandsModelTest < Minitest::Test
  def setup
    super
    @renderer = Rixie::CLI::Renderer.new
    @command = Rixie::CLI::Commands::Model.new(renderer: @renderer)
  end

  # -- name / description --

  def test_name
    assert_equal "model", @command.name
  end

  def test_description
    refute_empty @command.description
  end

  # -- call without argument --

  def test_call_without_arg_does_not_switch
    cli = FakeCLI.new(current_model: "gpt-4o", switched_to: nil)
    capture_io { @command.call(nil, cli: cli) }
    assert_nil cli.switched_to
  end

  # -- call with direct argument --

  def test_call_switches_model
    cli = FakeCLI.new(current_model: "gpt-4o", switched_to: nil)
    @command.call("claude-sonnet-4-6", cli: cli)
    assert_equal "claude-sonnet-4-6", cli.switched_to
  end

  def test_call_strips_whitespace
    cli = FakeCLI.new(current_model: "gpt-4o", switched_to: nil)
    @command.call("  claude-sonnet-4-6  ", cli: cli)
    assert_equal "claude-sonnet-4-6", cli.switched_to
  end

  def test_call_with_blank_string_does_not_switch
    cli = FakeCLI.new(current_model: "gpt-4o", switched_to: nil)
    @command.call("   ", cli: cli)
    assert_nil cli.switched_to
  end

  private

  FakeCLI = Struct.new(:current_model, :switched_to, keyword_init: true) do
    def switch_model(model)
      self.switched_to = model
    end
  end
end
