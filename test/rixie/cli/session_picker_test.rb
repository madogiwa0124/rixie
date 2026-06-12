# frozen_string_literal: true

require_relative "cli_test_helper"
require "rixie/cli/renderer"
require "rixie/cli/session_picker"

class CliSessionPickerTest < Minitest::Test
  def make_row(session_id:, updated_at: "2026-01-01T00:00:00Z", entry_count: 1, preview: "hello")
    Rixie::Store::Row.new(
      session_id: session_id,
      created_at: updated_at,
      updated_at: updated_at,
      entry_count: entry_count,
      preview: preview
    )
  end

  def make_store(rows)
    store = Object.new
    store.define_singleton_method(:list_sessions) { |limit: nil| rows }
    store
  end

  def make_picker(rows)
    Rixie::CLI::SessionPicker.new(store: make_store(rows), renderer: Rixie::CLI::Renderer.new)
  end

  def test_pick_returns_nil_when_no_saved_sessions
    picker = make_picker([])

    out, _err = capture_io do
      assert_nil picker.pick
    end
    assert_match(/No saved sessions found/, out)
  end

  def test_pick_returns_selected_session_id
    picker = make_picker([make_row(session_id: "s1"), make_row(session_id: "s2")])

    Reline.stub(:readline, ->(_p, _h) { "2" }) do
      out, _err = capture_io do
        assert_equal "s2", picker.pick
      end
      assert_match(/Saved sessions:/, out)
      assert_match(/s1/, out)
      assert_match(/s2/, out)
    end
  end

  def test_pick_returns_nil_on_empty_input
    picker = make_picker([make_row(session_id: "s1")])

    Reline.stub(:readline, ->(_p, _h) { "" }) do
      capture_io { assert_nil picker.pick }
    end
  end

  def test_pick_returns_nil_on_eof
    picker = make_picker([make_row(session_id: "s1")])

    Reline.stub(:readline, nil) do
      capture_io { assert_nil picker.pick }
    end
  end

  def test_pick_reprompts_on_invalid_input
    picker = make_picker([make_row(session_id: "s1")])
    inputs = ["abc", "9", "1"]

    Reline.stub(:readline, ->(_p, _h) { inputs.shift }) do
      out, _err = capture_io do
        assert_equal "s1", picker.pick
      end
      assert_equal 2, out.scan("Please enter a number between 1 and 1").size
    end
  end

  def test_pick_passes_limit_to_store
    captured = nil
    store = Object.new
    store.define_singleton_method(:list_sessions) { |limit: nil|
      captured = limit
      []
    }
    picker = Rixie::CLI::SessionPicker.new(store: store, renderer: Rixie::CLI::Renderer.new)

    capture_io { picker.pick(limit: 5) }
    assert_equal 5, captured
  end
end
