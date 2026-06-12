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

  # -- saved_sessions --

  def make_row(session_id:, updated_at:, entry_count: 2, preview: "hello world")
    Rixie::Store::Row.new(
      session_id: session_id,
      created_at: updated_at,
      updated_at: updated_at,
      entry_count: entry_count,
      preview: preview
    )
  end

  def test_saved_sessions_renders_numbered_rows_with_metadata
    rows = [
      make_row(session_id: "s1", updated_at: "2026-01-02T03:04:00Z"),
      make_row(session_id: "s2", updated_at: "2026-01-03T03:04:00Z", preview: "second")
    ]

    out, _err = capture_io { @renderer.saved_sessions(rows) }

    assert_match(/Saved sessions:/, out)
    assert_match(/1\./, out)
    assert_match(/s1 \(2 entries, updated: \d{4}-\d{2}-\d{2} \d{2}:\d{2}\) — hello world/, out)
    assert_match(/2\./, out)
    assert_match(/second/, out)
    assert_match(/Press Enter to cancel/, out)
  end

  def test_saved_sessions_shows_unknown_for_missing_updated_at
    out, _err = capture_io { @renderer.saved_sessions([make_row(session_id: "s1", updated_at: nil)]) }
    assert_match(/updated: unknown/, out)
  end

  def test_saved_sessions_omits_timestamp_for_unparsable_updated_at
    out, _err = capture_io { @renderer.saved_sessions([make_row(session_id: "s1", updated_at: "not-a-time")]) }
    assert_match(/s1 \(2 entries\) — hello world/, out)
  end
end
