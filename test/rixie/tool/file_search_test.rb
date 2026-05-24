# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class Rixie::Tool::FileSearchTest < Minitest::Test
  def setup
    super
    @tmpdir = Dir.mktmpdir("rixie_file_search")
    File.write(File.join(@tmpdir, "a.rb"), "def hello\n  puts 'hi'\nend\n")
    File.write(File.join(@tmpdir, "b.rb"), "def goodbye\n  puts 'bye'\nend\n")
    FileUtils.mkdir_p(File.join(@tmpdir, "lib"))
    File.write(File.join(@tmpdir, "lib", "c.rb"), "def hello_lib\nend\n")
    File.binwrite(File.join(@tmpdir, "binary.bin"), "hello\0world")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
    super
  end

  def tool(root: @tmpdir)
    Rixie::Tool::FileSearch.with(root_dir: root)
  end

  def test_is_a_tool_instance
    assert_instance_of Rixie::Tool, Rixie::Tool::FileSearch
  end

  def test_tool_name_is_file_search
    assert_equal "file_search", Rixie::Tool::FileSearch.name
  end

  def test_finds_matches_in_format_path_lineno_content
    output = tool.call({"pattern" => "hello"})
    lines = output.split("\n")
    assert_includes lines, "a.rb:1:def hello"
    assert_includes lines, "lib/c.rb:1:def hello_lib"
  end

  def test_matches_multiple_files
    output = tool.call({"pattern" => "puts"})
    lines = output.split("\n")
    assert_includes lines, "a.rb:2:  puts 'hi'"
    assert_includes lines, "b.rb:2:  puts 'bye'"
  end

  def test_glob_filter_restricts_files
    output = tool.call({"pattern" => "hello", "glob" => "lib/**/*.rb"})
    assert_equal "lib/c.rb:1:def hello_lib", output
  end

  def test_max_results_caps_output
    output = tool.call({"pattern" => "def", "max_results" => 1})
    assert_equal 1, output.split("\n").size
  end

  def test_skips_binary_files
    output = tool.call({"pattern" => "hello"})
    refute_match "binary.bin", output
  end

  def test_no_match_returns_message
    assert_equal "No matches found.", tool.call({"pattern" => "xyzzy_no_match"})
  end

  def test_invalid_regex_returns_error
    assert_match(/invalid regex/, tool.call({"pattern" => "[unclosed"}))
  end

  def test_default_root_dir_is_pwd
    Dir.chdir(@tmpdir) do
      output = Rixie::Tool::FileSearch.call({"pattern" => "hello"})
      assert_match "a.rb:1:def hello", output
    end
  end
end
