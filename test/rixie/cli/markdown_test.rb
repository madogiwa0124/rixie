# frozen_string_literal: true

require_relative "cli_test_helper"
require "rixie/cli/markdown"

class CliMarkdownTest < Minitest::Test
  FakeTerminal = Struct.new(:noop) do
    def bold(text) = "[B]#{text}[/B]"
    def italic(text) = "[I]#{text}[/I]"
    def accent(text) = "[A]#{text}[/A]"
    def secondary(text) = "[S]#{text}[/S]"
  end

  def setup
    super
    @terminal = FakeTerminal.new
  end

  def render(text)
    Rixie::CLI::Markdown.render(text, terminal: @terminal)
  end

  # -- headings --

  def test_h1_has_double_underline_matching_text_width
    assert_equal "[B][A]Hello[/A][/B]\n[A]═════[/A]", render("# Hello")
  end

  def test_h2_has_single_underline_matching_text_width
    assert_equal "[B][A]World[/A][/B]\n[A]─────[/A]", render("## World")
  end

  def test_h3_has_no_underline
    assert_equal "[B][A]Section[/A][/B]", render("### Section")
  end

  def test_h1_underline_accounts_for_cjk_width
    # "Ruby" = 4, "（" = 2, "ルビー" = 6, "）" = 2 → total 14
    assert_equal "[B][A]Ruby（ルビー）[/A][/B]\n[A]══════════════[/A]", render("# Ruby（ルビー）")
  end

  def test_heading_with_inline_bold
    assert_equal "[B][A]Hello [B]world[/B][/A][/B]\n[A]───────────[/A]", render("## Hello **world**")
  end

  def test_heading_underline_excludes_markdown_chars
    # "**bold**" markdown chars stripped → "bold" width 4
    assert_equal "[B][A][B]bold[/B][/A][/B]\n[A]════[/A]", render("# **bold**")
  end

  def test_heading_marker_requires_space
    assert_equal "#NoSpace", render("#NoSpace")
  end

  # -- bold --

  def test_inline_bold
    assert_equal "Hello [B]world[/B]", render("Hello **world**")
  end

  def test_multiple_bolds_on_same_line
    assert_equal "[B]a[/B] and [B]b[/B]", render("**a** and **b**")
  end

  def test_unclosed_bold_is_unchanged
    assert_equal "**unclosed", render("**unclosed")
  end

  # -- italic --

  def test_inline_italic
    assert_equal "Hello [I]world[/I]", render("Hello *world*")
  end

  def test_italic_does_not_match_inside_bold
    assert_equal "[B]bold[/B] and [I]italic[/I]", render("**bold** and *italic*")
  end

  def test_multiple_italics_on_same_line
    assert_equal "[I]a[/I] and [I]b[/I]", render("*a* and *b*")
  end

  def test_italic_whole_line
    assert_equal "[I]a question for you[/I]", render("*a question for you*")
  end

  def test_unclosed_italic_is_unchanged
    assert_equal "*unclosed", render("*unclosed")
  end

  # -- bullet list --

  def test_dash_bullet_list
    assert_equal "[A]•[/A] item one", render("- item one")
  end

  def test_asterisk_bullet_list
    assert_equal "[A]•[/A] item one", render("* item one")
  end

  def test_indented_bullet_preserves_indent
    assert_equal "  [A]•[/A] nested", render("  - nested")
  end

  def test_bullet_with_inline_bold
    assert_equal "[A]•[/A] item with [B]bold[/B]", render("- item with **bold**")
  end

  # -- numbered list --

  def test_numbered_list
    assert_equal "[A]1.[/A] first", render("1. first")
  end

  def test_numbered_list_preserves_number
    assert_equal "[A]42.[/A] forty-two", render("42. forty-two")
  end

  # -- plain text --

  def test_plain_text_passes_through
    assert_equal "just some prose", render("just some prose")
  end

  def test_empty_line_is_preserved
    assert_equal "a\n\nb", render("a\n\nb")
  end

  # -- multi-line --

  def test_full_document
    input = <<~MD.chomp
      # Title

      Some intro with **bold** text.

      ## Section
      - first item
      - second **emphasized**
    MD
    expected = [
      "[B][A]Title[/A][/B]",
      "[A]═════[/A]",
      "",
      "Some intro with [B]bold[/B] text.",
      "",
      "[B][A]Section[/A][/B]",
      "[A]───────[/A]",
      "[A]•[/A] first item",
      "[A]•[/A] second [B]emphasized[/B]"
    ].join("\n")
    assert_equal expected, render(input)
  end
end
