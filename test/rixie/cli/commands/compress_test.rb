# frozen_string_literal: true

require_relative "../cli_test_helper"
require "rixie/cli/renderer"
require "rixie/cli/commands"

class CliCommandsCompressTest < Minitest::Test
  def setup
    super
    @renderer = Rixie::CLI::Renderer.new
    @command = Rixie::CLI::Commands::Compress.new(renderer: @renderer)
  end

  # -- name / description --

  def test_name
    assert_equal "compress", @command.name
  end

  def test_description
    refute_empty @command.description
  end

  # -- call with empty context --

  def test_call_with_empty_context_does_not_compress
    cli = FakeCLI.new(context_length: 0, context_size_values: [0])
    capture_io { @command.call(nil, cli: cli) }
    assert_nil cli.compressed_with
  end

  def test_call_with_empty_context_shows_info
    cli = FakeCLI.new(context_length: 0, context_size_values: [0])
    out, = capture_io { @command.call(nil, cli: cli) }
    assert_match "Already empty", out
  end

  # -- call without argument --

  def test_call_without_arg_compresses_with_keep_recent_zero
    cli = FakeCLI.new(context_length: 5, context_size_values: [100, 10])
    capture_io { @command.call(nil, cli: cli) }
    assert_equal 0, cli.compressed_with
  end

  def test_call_without_arg_shows_before_after_size
    cli = FakeCLI.new(context_length: 5, context_size_values: [100, 10])
    out, = capture_io { @command.call(nil, cli: cli) }
    assert_match "~100", out
    assert_match "~10", out
  end

  # -- context grew after compression --

  def test_call_shows_notice_when_context_grows
    cli = FakeCLI.new(context_length: 5, context_size_values: [48, 79])
    out, = capture_io { @command.call(nil, cli: cli) }
    assert_match "~48", out
    assert_match "~79", out
    assert_match "did not reduce", out
  end

  def test_call_shows_notice_when_context_unchanged
    cli = FakeCLI.new(context_length: 5, context_size_values: [50, 50])
    out, = capture_io { @command.call(nil, cli: cli) }
    assert_match "did not reduce", out
  end

  # -- call with keep_recent argument --

  def test_call_with_keep_recent_passes_value
    cli = FakeCLI.new(context_length: 5, context_size_values: [200, 50])
    capture_io { @command.call("2", cli: cli) }
    assert_equal 2, cli.compressed_with
  end

  # -- invalid argument --

  def test_call_with_invalid_arg_shows_error
    cli = FakeCLI.new(context_length: 5, context_size_values: [100])
    out, = capture_io { @command.call("abc", cli: cli) }
    assert_match "Invalid argument", out
    assert_nil cli.compressed_with
  end

  def test_call_with_negative_arg_shows_error
    cli = FakeCLI.new(context_length: 5, context_size_values: [100])
    out, = capture_io { @command.call("-1", cli: cli) }
    assert_match "Invalid argument", out
    assert_nil cli.compressed_with
  end

  private

  class FakeCLI
    attr_accessor :compressed_with

    def initialize(context_length:, context_size_values:)
      @context_length = context_length
      @context_size_values = context_size_values.dup
      @compressed_with = nil
    end

    def current_context_length = @context_length
    def current_context_size = @context_size_values.shift
    def compress!(keep_recent: 0) = (self.compressed_with = keep_recent)
  end
end
