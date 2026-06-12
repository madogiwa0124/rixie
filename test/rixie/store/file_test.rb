# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

class FileStoreTest < Minitest::Test
  def make_history(input: "Hello", output: "Hi", thoughts: [])
    Rixie::Context::History.new(input: input, thoughts: thoughts, output: output)
  end

  def make_summary(content: "Summary text")
    Rixie::Context::Summary.new(content: content)
  end

  def with_store
    Dir.mktmpdir do |dir|
      path = ::File.join(dir, "sessions.json")
      yield Rixie::Store::File.new(path: path), path
    end
  end

  def test_save_and_load_round_trip_context
    with_store do |store, _path|
      store.save("s1", [make_summary(content: "short"), make_history(input: "Q", output: "A")])

      loaded = store.load("s1")
      assert_equal 2, loaded.size
      assert_instance_of Rixie::Context::Summary, loaded.first
      assert_instance_of Rixie::Context::History, loaded.last
    end
  end

  def test_load_returns_empty_array_for_unknown_session
    with_store do |store, _path|
      assert_equal [], store.load("unknown")
    end
  end

  def test_save_creates_store_file
    with_store do |store, path|
      refute ::File.exist?(path)
      store.save("s1", [make_history])
      assert ::File.exist?(path)
    end
  end

  def test_list_sessions_returns_latest_first
    with_store do |store, path|
      payload = {
        "sessions" => {
          "old" => {
            "created_at" => "2026-01-01T00:00:00Z",
            "updated_at" => "2026-01-01T00:00:00Z",
            "entries" => [{"type" => "history", "input" => "old input", "thoughts" => [], "output" => "old output"}]
          },
          "new" => {
            "created_at" => "2026-01-02T00:00:00Z",
            "updated_at" => "2026-01-02T00:00:00Z",
            "entries" => [{"type" => "history", "input" => "new input", "thoughts" => [], "output" => "new output"}]
          }
        }
      }
      ::File.write(path, JSON.pretty_generate(payload))

      sessions = store.list_sessions
      assert_equal %w[new old], sessions.map(&:session_id)
      assert_equal "new input", sessions.first.preview
      assert_equal 1, sessions.first.entry_count
    end
  end

  def test_list_sessions_respects_limit
    with_store do |store, path|
      payload = {
        "sessions" => {
          "s1" => {"created_at" => "2026-01-01T00:00:00Z", "updated_at" => "2026-01-01T00:00:00Z", "entries" => []},
          "s2" => {"created_at" => "2026-01-02T00:00:00Z", "updated_at" => "2026-01-02T00:00:00Z", "entries" => []}
        }
      }
      ::File.write(path, JSON.pretty_generate(payload))

      sessions = store.list_sessions(limit: 1)
      assert_equal 1, sessions.size
      assert_equal "s2", sessions.first.session_id
    end
  end

  def test_load_raises_for_invalid_json
    with_store do |store, path|
      ::File.write(path, "not-json")

      assert_raises(Rixie::Error) do
        store.load("s1")
      end
    end
  end

  def test_deserialize_raises_for_unknown_type
    assert_raises(Rixie::Error) do
      Rixie::Store::File.deserialize("type" => "unknown")
    end
  end
end
