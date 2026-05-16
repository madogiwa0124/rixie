# frozen_string_literal: true

require_relative "cli_test_helper"
require "rixie/cli/renderer"

class CliRendererTest < Minitest::Test
  def setup
    super
    @renderer = Rixie::CLI::Renderer.new
  end

  # -- format_tool_args (via render_tool_call) --

  def test_format_tool_args_with_simple_values
    result = @renderer.send(:format_tool_args, {"query" => "Ruby news", "limit" => 10})
    assert_equal 2, result.size
    assert_match(/query/, result[0])
    assert_match(/Ruby news/, result[0])
    assert_match(/limit/, result[1])
    assert_match(/10/, result[1])
  end

  def test_format_tool_args_with_array_of_hashes
    args = {"steps" => [{"title" => "Step 1", "description" => "Do it"}]}
    result = @renderer.send(:format_tool_args, args)
    assert_operator result.size, :>=, 2
    assert_match(/steps/, result[0])
    assert_match(/title: Step 1/, result[1])
  end

  def test_format_tool_args_with_array_of_strings
    args = {"tags" => %w[ruby ai agent]}
    result = @renderer.send(:format_tool_args, args)
    assert_operator result.size, :>=, 4
    assert_match(/ruby/, result[1])
    assert_match(/ai/, result[2])
    assert_match(/agent/, result[3])
  end

  def test_format_tool_args_with_nil
    assert_empty @renderer.send(:format_tool_args, nil)
  end

  def test_format_tool_args_with_empty_hash
    assert_empty @renderer.send(:format_tool_args, {})
  end

  # -- prompt --

  def test_prompt_simple_has_no_strategy_label
    result = @renderer.prompt("simple")
    refute_match(/simple/, result)
  end

  def test_prompt_non_simple_includes_strategy_name
    result = @renderer.prompt("plan-execute")
    assert_match(/plan-execute/, result)
  end
end
