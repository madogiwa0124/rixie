# frozen_string_literal: true

module Rixie
  class CLI
    module Markdown
      HEADING_RE = /\A(\#{1,6})\s+(.+)\z/
      BULLET_RE = /\A(\s*)[-*]\s+(.+)\z/
      NUMBERED_RE = /\A(\s*)(\d+)\.\s+(.+)\z/
      BOLD_RE = /\*\*([^*\n]+)\*\*/
      ITALIC_RE = /(?<!\*)\*([^*\n]+)\*(?!\*)/

      module_function

      def render(text, terminal:)
        text.split("\n", -1).map { |line| render_line(line, terminal:) }.join("\n")
      end

      def render_line(line, terminal:)
        case line
        when HEADING_RE
          level = ::Regexp.last_match(1).length
          raw = ::Regexp.last_match(2)
          rendered = render_inline(raw, terminal:)
          render_heading(rendered, raw: raw, level: level, terminal: terminal)
        when BULLET_RE
          indent = ::Regexp.last_match(1)
          content = render_inline(::Regexp.last_match(2), terminal:)
          "#{indent}#{terminal.accent("•")} #{content}"
        when NUMBERED_RE
          indent = ::Regexp.last_match(1)
          num = ::Regexp.last_match(2)
          content = render_inline(::Regexp.last_match(3), terminal:)
          "#{indent}#{terminal.accent("#{num}.")} #{content}"
        else
          render_inline(line, terminal:)
        end
      end

      def render_heading(rendered, raw:, level:, terminal:)
        styled = terminal.bold(terminal.accent(rendered))
        case level
        when 1 then "#{styled}\n#{terminal.accent("═" * visual_width(raw))}"
        when 2 then "#{styled}\n#{terminal.accent("─" * visual_width(raw))}"
        else styled
        end
      end

      def render_inline(text, terminal:)
        text
          .gsub(BOLD_RE) { terminal.bold(::Regexp.last_match(1)) }
          .gsub(ITALIC_RE) { terminal.italic(::Regexp.last_match(1)) }
      end

      def visual_width(text)
        text.gsub(/\*+/, "").each_char.sum { |c| (c.bytesize > 1) ? 2 : 1 }
      end
    end
  end
end
