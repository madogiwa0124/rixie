# frozen_string_literal: true

require "test_helper"

class MemoryStoreTest < Minitest::Test
  def store
    @store ||= Rixie::Store::Memory.new
  end

  def test_save_stores_context_by_session_id
    store.save("s1", ["entry1"])
    assert_equal ["entry1"], store.load("s1")
  end

  def test_load_returns_stored_context
    store.save("s2", ["a", "b"])
    assert_equal ["a", "b"], store.load("s2")
  end

  def test_load_returns_empty_array_for_unknown_session_id
    assert_equal [], store.load("nonexistent")
  end

  def test_save_overwrites_existing_entry
    store.save("s3", ["old"])
    store.save("s3", ["new"])
    assert_equal ["new"], store.load("s3")
  end
end
