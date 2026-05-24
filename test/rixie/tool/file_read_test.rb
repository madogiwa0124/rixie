# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class Rixie::Tool::FileReadTest < Minitest::Test
  def setup
    super
    @tmpdir = Dir.mktmpdir("rixie_file_read")
    File.write(File.join(@tmpdir, "hello.txt"), "line 1\nline 2\nline 3\n")
    FileUtils.mkdir_p(File.join(@tmpdir, "sub"))
    File.write(File.join(@tmpdir, "sub", "nested.txt"), "nested content\n")
    File.binwrite(File.join(@tmpdir, "binary.bin"), "abc\0def")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
    super
  end

  def tool(root: @tmpdir)
    Rixie::Tool::FileRead.with(root_dir: root)
  end

  def test_is_a_tool_instance
    assert_instance_of Rixie::Tool, Rixie::Tool::FileRead
  end

  def test_tool_name_is_file_read
    assert_equal "file_read", Rixie::Tool::FileRead.name
  end

  def test_reads_file_relative_to_root
    assert_equal "line 1\nline 2\nline 3\n", tool.call({"path" => "hello.txt"})
  end

  def test_reads_nested_file
    assert_equal "nested content\n", tool.call({"path" => "sub/nested.txt"})
  end

  def test_offset_skips_lines
    assert_equal "line 2\nline 3\n", tool.call({"path" => "hello.txt", "offset" => 2})
  end

  def test_limit_caps_lines
    assert_equal "line 1\nline 2\n", tool.call({"path" => "hello.txt", "limit" => 2})
  end

  def test_offset_and_limit_together
    assert_equal "line 2\n", tool.call({"path" => "hello.txt", "offset" => 2, "limit" => 1})
  end

  def test_rejects_path_with_dotdot_segment
    assert_match(/contains '\.\.' segment/, tool.call({"path" => "../escape.txt"}))
  end

  def test_rejects_absolute_path_outside_root
    assert_match(/outside root_dir/, tool.call({"path" => "/etc/passwd"}))
  end

  def test_returns_error_for_missing_file
    assert_match(/Error/, tool.call({"path" => "does_not_exist.txt"}))
  end

  def test_returns_error_for_directory
    assert_match(/Error/, tool.call({"path" => "sub"}))
  end

  def test_returns_error_for_binary_file
    assert_match(/Binary file not supported/, tool.call({"path" => "binary.bin"}))
  end

  def test_default_root_dir_is_pwd
    Dir.chdir(@tmpdir) do
      assert_equal "line 1\nline 2\nline 3\n", Rixie::Tool::FileRead.call({"path" => "hello.txt"})
    end
  end

  def test_with_returns_a_tool_instance
    assert_instance_of Rixie::Tool, Rixie::Tool::FileRead.with(root_dir: @tmpdir)
  end

  def test_with_returns_a_different_instance_from_default
    refute_same Rixie::Tool::FileRead, Rixie::Tool::FileRead.with(root_dir: @tmpdir)
  end
end
