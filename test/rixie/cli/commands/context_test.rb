# frozen_string_literal: true

require_relative "../cli_test_helper"
require "rixie/cli/renderer"
require "rixie/cli/commands"

class CliCommandsContextTest < Minitest::Test
  def setup
    super
    @renderer = Rixie::CLI::Renderer.new
    @command = Rixie::CLI::Commands::Context.new(renderer: @renderer)
  end

  # -- name / description --

  def test_name
    assert_equal "context", @command.name
  end

  def test_description
    refute_empty @command.description
  end

  # -- call --

  def test_call_displays_context_size
    cli = FakeCLI.new(current_context_size: 42, current_context_length: 3)
    out, = capture_io { @command.call(nil, cli: cli) }
    assert_match "~42 tokens", out
  end

  def test_call_displays_entry_count
    cli = FakeCLI.new(current_context_size: 0, current_context_length: 5)
    out, = capture_io { @command.call(nil, cli: cli) }
    assert_match "5", out
  end

  def test_call_with_zero_context
    cli = FakeCLI.new(current_context_size: 0, current_context_length: 0)
    out, = capture_io { @command.call(nil, cli: cli) }
    assert_match "~0 tokens", out
    assert_match "0", out
  end

  private

  FakeCLI = Struct.new(:current_context_size, :current_context_length)
end
