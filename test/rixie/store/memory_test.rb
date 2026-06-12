# frozen_string_literal: true

require "test_helper"

class MemoryStoreTest < Minitest::Test
  def store
    @store ||= Rixie::Store::Memory.new
  end

  def make_history(input: "Hello", output: "Hi", thoughts: [])
    Rixie::Context::History.new(input: input, thoughts: thoughts, output: output)
  end

  def make_summary(content: "Summary text")
    Rixie::Context::Summary.new(content: content)
  end

  def test_save_stores_context_by_session_id
    history = make_history
    store.save("s1", [history])
    loaded = store.load("s1")
    assert_equal 1, loaded.size
  end

  def test_load_returns_stored_context
    store.save("s2", [make_history(input: "a"), make_history(input: "b")])
    assert_equal 2, store.load("s2").size
  end

  def test_load_returns_empty_array_for_unknown_session_id
    assert_equal [], store.load("nonexistent")
  end

  def test_save_overwrites_existing_entry
    store.save("s3", [make_history(input: "old")])
    store.save("s3", [make_history(input: "new")])
    assert_equal 1, store.load("s3").size
  end

  def test_save_serializes_context_history
    history = make_history(input: "Hello", output: "Hi")
    store.save("s4", [history])
    raw = store.instance_variable_get(:@data)["s4"]
    assert_equal "history", raw.first["type"]
    assert_equal "Hello", raw.first["input"]
    assert_equal "Hi", raw.first["output"]
  end

  def test_save_serializes_context_summary
    summary = make_summary(content: "A summary")
    store.save("s5", [summary])
    raw = store.instance_variable_get(:@data)["s5"]
    assert_equal "summary", raw.first["type"]
    assert_equal "A summary", raw.first["content"]
  end

  def test_load_deserializes_context_history
    store.save("s6", [make_history(input: "Q", output: "A")])
    loaded = store.load("s6")
    assert_instance_of Rixie::Context::History, loaded.first
  end

  def test_load_deserializes_context_summary
    store.save("s7", [make_summary(content: "Brief")])
    loaded = store.load("s7")
    assert_instance_of Rixie::Context::Summary, loaded.first
    assert_equal "Brief", loaded.first.content
  end

  def test_load_returns_mixed_array_for_mixed_types
    store.save("s8", [make_history, make_summary])
    loaded = store.load("s8")
    assert_equal 2, loaded.size
    assert_instance_of Rixie::Context::History, loaded.first
    assert_instance_of Rixie::Context::Summary, loaded.last
  end

  def test_deserialize_raises_for_unknown_type
    assert_raises(Rixie::Error) do
      Rixie::Store::Memory.deserialize("type" => "unknown")
    end
  end

  def test_load_round_trips_history_input_and_output
    store.save("s9", [make_history(input: "ping", output: "pong")])
    loaded = store.load("s9")
    messages = loaded.first.to_message
    assert_equal "ping", messages.first.content
    assert_equal "pong", messages.last.content
  end

  def test_load_round_trips_summary_content
    store.save("s10", [make_summary(content: "recap")])
    loaded = store.load("s10")
    assert_equal "Previous conversation summary:\nrecap", loaded.first.to_message.first.content
  end

  def test_list_sessions_returns_rows_with_expected_shape
    store.save("s11", [make_history(input: "hello", output: "world")])

    sessions = store.list_sessions
    assert_equal 1, sessions.size
    assert_equal "s11", sessions.first.session_id
    assert_equal 1, sessions.first.entry_count
    assert_equal "hello", sessions.first.preview
  end

  def test_list_sessions_respects_limit
    store.save("s12", [make_history(input: "first")])
    store.save("s13", [make_history(input: "second")])

    sessions = store.list_sessions(limit: 1)
    assert_equal 1, sessions.size
  end
end
