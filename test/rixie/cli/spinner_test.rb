# frozen_string_literal: true

require_relative "cli_test_helper"
require "rixie/cli/terminal"
require "rixie/cli/spinner"

class CliSpinnerTest < Minitest::Test
  def setup
    super
    @io = StringIO.new
    @spinner = Rixie::CLI::Spinner.new(
      terminal: Rixie::CLI::Terminal.new,
      prefix: "  > ",
      io: @io
    )
  end

  def teardown
    @spinner.stop
  end

  def test_stopped_initially
    assert @spinner.stopped?
  end

  def test_start_marks_running
    @spinner.start
    refute @spinner.stopped?
  end

  def test_stop_after_start_marks_stopped
    @spinner.start
    @spinner.stop
    assert @spinner.stopped?
  end

  def test_start_when_already_running_is_noop
    @spinner.start
    thread = @spinner.instance_variable_get(:@thread)
    @spinner.start
    assert_equal thread, @spinner.instance_variable_get(:@thread)
  end

  def test_stop_when_already_stopped_is_noop
    assert @spinner.stopped?
    @spinner.stop
    assert @spinner.stopped?
  end

  def test_start_writes_to_injected_io
    @spinner.start
    sleep 0.15
    @spinner.stop
    refute_empty @io.string
  end
end
