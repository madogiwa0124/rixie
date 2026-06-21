# frozen_string_literal: true

require "test_helper"

class InputTest < Minitest::Test
  def test_string_is_passed_through_unchanged
    assert_equal "hello", Rixie::Input.normalize("hello")
  end

  def test_non_array_non_string_is_passed_through_unchanged
    assert_nil Rixie::Input.normalize(nil)
    assert_equal 42, Rixie::Input.normalize(42)
  end

  def test_text_block_is_canonicalized_to_string_keys
    result = Rixie::Input.normalize([{type: "text", text: "hi"}])
    assert_equal [{"type" => "text", "text" => "hi"}], result
  end

  def test_image_block_is_canonicalized_to_string_keys
    result = Rixie::Input.normalize([
      {type: "image", source: {type: "base64", media_type: "image/png", data: "QUJD"}}
    ])
    assert_equal(
      [{"type" => "image", "source" => {"type" => "base64", "media_type" => "image/png", "data" => "QUJD"}}],
      result
    )
  end

  def test_string_keyed_input_is_accepted_and_normalized
    # Content round-tripped through a JSON-backed store comes back with String keys.
    input = [
      {"type" => "text", "text" => "hi"},
      {"type" => "image", "source" => {"type" => "base64", "media_type" => "image/png", "data" => "XYZ"}}
    ]
    assert_equal input, Rixie::Input.normalize(input)
  end

  def test_mixed_text_and_image_preserves_order
    result = Rixie::Input.normalize([
      {type: "text", text: "What's in this image?"},
      {type: "image", source: {type: "base64", media_type: "image/png", data: "QUJD"}}
    ])
    assert_equal "text", result[0]["type"]
    assert_equal "image", result[1]["type"]
  end

  def test_raises_on_non_hash_block
    error = assert_raises(Rixie::InvalidContentError) { Rixie::Input.normalize(["hello"]) }
    assert_includes error.message, "expected a Hash"
  end

  def test_raises_on_unknown_block_type
    error = assert_raises(Rixie::InvalidContentError) do
      Rixie::Input.normalize([{type: "audio", data: "..."}])
    end
    assert_includes error.message, "Unknown content block type"
  end

  def test_raises_on_text_block_without_text
    error = assert_raises(Rixie::InvalidContentError) do
      Rixie::Input.normalize([{type: "text"}])
    end
    assert_includes error.message, "Invalid text content block"
  end

  def test_raises_on_non_hash_image_source
    error = assert_raises(Rixie::InvalidContentError) do
      Rixie::Input.normalize([{type: "image", source: "data:image/png;base64,AAA"}])
    end
    assert_includes error.message, "Invalid image source"
  end

  def test_raises_on_non_base64_image_source
    error = assert_raises(Rixie::InvalidContentError) do
      Rixie::Input.normalize([{type: "image", source: {type: "url", url: "https://example.com/a.png"}}])
    end
    assert_includes error.message, "Invalid image content block"
  end

  def test_raises_on_image_block_missing_data
    assert_raises(Rixie::InvalidContentError) do
      Rixie::Input.normalize([{type: "image", source: {type: "base64", media_type: "image/png"}}])
    end
  end

  def test_raises_on_image_block_with_empty_data
    assert_raises(Rixie::InvalidContentError) do
      Rixie::Input.normalize([{type: "image", source: {type: "base64", media_type: "image/png", data: ""}}])
    end
  end

  def test_raises_on_image_block_with_empty_media_type
    assert_raises(Rixie::InvalidContentError) do
      Rixie::Input.normalize([{type: "image", source: {type: "base64", media_type: "", data: "QUJD"}}])
    end
  end

  def test_invalid_content_error_is_a_rixie_error_but_not_llm_error
    # Terminal caller-input error — must be catchable as Rixie::Error yet
    # distinguishable from LLM::Error (a possibly-transient provider failure).
    assert Rixie::InvalidContentError < Rixie::Error
    refute Rixie::InvalidContentError < Rixie::LLM::Error
  end
end
