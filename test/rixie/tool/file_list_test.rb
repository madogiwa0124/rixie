# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class Rixie::Tool::FileListTest < Minitest::Test
  def setup
    super
    @tmpdir = Dir.mktmpdir("rixie_file_list")
    File.write(File.join(@tmpdir, "a.rb"), "")
    File.write(File.join(@tmpdir, "b.rb"), "")
    File.write(File.join(@tmpdir, "c.txt"), "")
    FileUtils.mkdir_p(File.join(@tmpdir, "lib"))
    File.write(File.join(@tmpdir, "lib", "d.rb"), "")
    File.write(File.join(@tmpdir, "lib", "e.rb"), "")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
    super
  end

  def tool(root: @tmpdir)
    Rixie::Tool::FileList.with(root_dir: root)
  end

  def test_is_a_tool_instance
    assert_instance_of Rixie::Tool, Rixie::Tool::FileList
  end

  def test_tool_name_is_file_list
    assert_equal "file_list", Rixie::Tool::FileList.name
  end

  def test_top_level_glob
    output = tool.call({"pattern" => "*.rb"})
    assert_equal "a.rb\nb.rb", output
  end

  def test_recursive_glob
    output = tool.call({"pattern" => "**/*.rb"})
    lines = output.split("\n")
    assert_includes lines, "a.rb"
    assert_includes lines, "b.rb"
    assert_includes lines, "lib/d.rb"
    assert_includes lines, "lib/e.rb"
  end

  def test_directory_glob
    output = tool.call({"pattern" => "lib/*"})
    assert_equal "lib/d.rb\nlib/e.rb", output
  end

  def test_results_are_sorted
    output = tool.call({"pattern" => "*.rb"})
    assert_equal output.split("\n").sort, output.split("\n")
  end

  def test_filters_paths_escaping_root
    # `../*` glob would resolve outside root and must be filtered out.
    output = tool.call({"pattern" => "../*"})
    assert_equal "No files matched.", output
  end

  def test_no_match_returns_message
    assert_equal "No files matched.", tool.call({"pattern" => "*.xyz"})
  end

  def test_default_root_dir_is_pwd
    Dir.chdir(@tmpdir) do
      output = Rixie::Tool::FileList.call({"pattern" => "*.rb"})
      assert_equal "a.rb\nb.rb", output
    end
  end
end
