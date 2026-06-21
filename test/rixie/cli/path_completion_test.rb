# frozen_string_literal: true

require_relative "cli_test_helper"
require "rixie/cli/path_completion"
require "tmpdir"

class CliPathCompletionTest < Minitest::Test
  # Builds a temp dir with: sample.png, photo.jpg, notes.txt, and a sub/ directory.
  def with_dir
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "sample.png"), "x")
      File.binwrite(File.join(dir, "photo.jpg"), "x")
      File.write(File.join(dir, "notes.txt"), "x")
      Dir.mkdir(File.join(dir, "sub"))
      yield dir
    end
  end

  def test_returns_empty_when_no_at_token
    assert_equal [], Rixie::CLI::PathCompletion.complete("just some text")
  end

  def test_returns_empty_when_at_token_not_at_end
    assert_equal [], Rixie::CLI::PathCompletion.complete("@a.png and more text")
  end

  def test_lists_images_and_dirs_but_not_other_files
    with_dir do |dir|
      result = Rixie::CLI::PathCompletion.complete("look @#{dir}/")
      tokens = result.map { |c| c.delete_prefix("look @") }
      assert_includes tokens, "#{dir}/photo.jpg"
      assert_includes tokens, "#{dir}/sample.png"
      assert_includes tokens, "#{dir}/sub/"
      refute_includes tokens, "#{dir}/notes.txt"
    end
  end

  def test_directories_get_trailing_slash
    with_dir do |dir|
      result = Rixie::CLI::PathCompletion.complete("@#{dir}/sub")
      assert_equal ["@#{dir}/sub/"], result
    end
  end

  def test_filters_by_fragment
    with_dir do |dir|
      result = Rixie::CLI::PathCompletion.complete("@#{dir}/sa")
      assert_equal ["@#{dir}/sample.png"], result
    end
  end

  def test_preserves_text_before_the_token
    with_dir do |dir|
      result = Rixie::CLI::PathCompletion.complete("describe this @#{dir}/sa")
      assert_equal ["describe this @#{dir}/sample.png"], result
    end
  end

  def test_completes_relative_paths_against_cwd
    with_dir do |dir|
      Dir.chdir(dir) do
        result = Rixie::CLI::PathCompletion.complete("@sa")
        assert_equal ["@sample.png"], result
      end
    end
  end

  def test_empty_partial_lists_cwd_entries
    with_dir do |dir|
      Dir.chdir(dir) do
        tokens = Rixie::CLI::PathCompletion.complete("@").map { |c| c.delete_prefix("@") }
        assert_equal ["photo.jpg", "sample.png", "sub/"], tokens
      end
    end
  end

  def test_hides_dotfiles_unless_fragment_starts_with_dot
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, ".secret.png"), "x")
      File.binwrite(File.join(dir, "open.png"), "x")
      Dir.chdir(dir) do
        assert_equal ["@open.png"], Rixie::CLI::PathCompletion.complete("@")
        assert_equal ["@.secret.png"], Rixie::CLI::PathCompletion.complete("@.")
      end
    end
  end

  def test_unreadable_or_missing_directory_yields_no_candidates
    assert_equal [], Rixie::CLI::PathCompletion.complete("@/no/such/dir/x")
  end
end
