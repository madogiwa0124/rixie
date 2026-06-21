# frozen_string_literal: true

require_relative "cli_test_helper"
require "rixie/cli/image_input"
require "tmpdir"
require "base64"
require "minitest/mock"

class CliImageInputTest < Minitest::Test
  def with_image(name: "photo.png", bytes: "\x89PNG\r\n\x1a\n binary")
    Dir.mktmpdir do |dir|
      path = File.join(dir, name)
      File.binwrite(path, bytes)
      yield path, bytes
    end
  end

  def test_plain_text_returns_string_unchanged
    assert_equal "what is 2 + 2?", Rixie::CLI::ImageInput.parse("what is 2 + 2?")
  end

  def test_text_with_image_returns_text_and_image_blocks
    with_image do |path, bytes|
      result = Rixie::CLI::ImageInput.parse("What's in this? @#{path}")
      assert_instance_of Array, result
      assert_equal({type: "text", text: "What's in this?"}, result[0])
      assert_equal "image", result[1][:type]
      assert_equal "image/png", result[1][:source][:media_type]
      assert_equal "base64", result[1][:source][:type]
      assert_equal Base64.strict_encode64(bytes), result[1][:source][:data]
    end
  end

  def test_image_only_message_omits_text_block
    with_image do |path, _|
      result = Rixie::CLI::ImageInput.parse("@#{path}")
      assert_equal 1, result.size
      assert_equal "image", result[0][:type]
    end
  end

  def test_multiple_images
    with_image(name: "a.png") do |a, _|
      with_image(name: "b.jpg") do |b, _|
        result = Rixie::CLI::ImageInput.parse("compare @#{a} @#{b}")
        types = result.map { |b2| b2[:type] }
        assert_equal ["text", "image", "image"], types
        assert_equal "image/jpeg", result[2][:source][:media_type]
      end
    end
  end

  def test_at_token_for_nonexistent_image_is_left_as_text
    result = Rixie::CLI::ImageInput.parse("email me @nope.png please")
    assert_equal "email me @nope.png please", result
  end

  def test_at_token_for_non_image_file_is_left_as_text
    Dir.mktmpdir do |dir|
      path = File.join(dir, "notes.txt")
      File.write(path, "hi")
      result = Rixie::CLI::ImageInput.parse("read @#{path}")
      assert_equal "read @#{path}", result
    end
  end

  def test_unreadable_existing_image_is_left_as_text
    with_image do |path, _|
      File.stub(:readable?, false) do
        assert_equal "look @#{path}", Rixie::CLI::ImageInput.parse("look @#{path}")
      end
    end
  end

  def test_image_that_fails_to_read_raises_rixie_error_not_system_call_error
    # Simulates the file vanishing / losing read permission between the
    # image_token? check and the binread (a TOCTOU race the CLI must not crash on).
    with_image do |path, _|
      File.stub(:binread, ->(*) { raise Errno::EACCES, path }) do
        error = assert_raises(Rixie::Error) do
          Rixie::CLI::ImageInput.parse("look @#{path}")
        end
        assert_includes error.message, "Could not read image file"
      end
    end
  end
end
