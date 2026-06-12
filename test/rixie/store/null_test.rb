# frozen_string_literal: true

require "test_helper"

class NullStoreTest < Minitest::Test
  def store
    @store ||= Rixie::Store::Null.new
  end

  def test_save_is_a_noop
    assert_nil store.save("s1", ["data"])
  end

  def test_load_always_returns_empty_array
    store.save("s1", ["data"])
    assert_equal [], store.load("s1")
  end

  def test_list_sessions_returns_empty_array
    assert_equal [], store.list_sessions
  end
end
