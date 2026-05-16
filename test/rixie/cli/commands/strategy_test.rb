# frozen_string_literal: true

require_relative "../cli_test_helper"
require "rixie/cli/renderer"
require "rixie/cli/commands"

class CliCommandsStrategyTest < Minitest::Test
  def setup
    super
    @renderer = Rixie::CLI::Renderer.new
    @command = Rixie::CLI::Commands::Strategy.new(renderer: @renderer)
  end

  # -- name / description --

  def test_name
    assert_equal "strategy", @command.name
  end

  def test_description
    refute_empty @command.description
  end

  # -- resolve --

  def test_resolve_simple
    strategy = @command.resolve("simple")
    assert_instance_of Rixie::Strategy::Simple, strategy
  end

  def test_resolve_plan_execute
    strategy = @command.resolve("plan-execute")
    assert_instance_of Rixie::Strategy::PlanExecute, strategy
  end

  def test_resolve_unknown_returns_nil
    assert_nil @command.resolve("unknown")
  end

  # -- complete --

  def test_complete_with_partial_match
    assert_equal ["/strategy plan-execute"], @command.complete("/strategy p")
  end

  def test_complete_with_full_match
    assert_equal ["/strategy simple"], @command.complete("/strategy simple")
  end

  def test_complete_with_empty_prefix_returns_all
    candidates = @command.complete("/strategy ")
    assert_includes candidates, "/strategy simple"
    assert_includes candidates, "/strategy plan-execute"
  end

  def test_complete_with_no_match
    assert_empty @command.complete("/strategy xyz")
  end

  # -- call without argument --

  def test_call_without_arg_does_not_change_strategy
    cli = FakeCLI.new(strategy_name: "simple")
    capture_io { @command.call(nil, cli: cli) }
    assert_equal "simple", cli.strategy_name
  end

  # -- call with direct argument --

  def test_call_sets_valid_strategy
    cli = FakeCLI.new(strategy_name: "simple")
    @command.call("plan-execute", cli: cli)
    assert_equal "plan-execute", cli.strategy_name
  end

  def test_call_strips_whitespace
    cli = FakeCLI.new(strategy_name: "simple")
    @command.call("  plan-execute  ", cli: cli)
    assert_equal "plan-execute", cli.strategy_name
  end

  def test_call_with_invalid_strategy_does_not_change
    cli = FakeCLI.new(strategy_name: "simple")
    @command.call("unknown", cli: cli)
    assert_equal "simple", cli.strategy_name
  end

  private

  FakeCLI = Struct.new(:strategy_name, keyword_init: true)
end
