# frozen_string_literal: true

require "cli/ui"

module Rixie
  class CLI
    class Terminal
      def self.enable_stdout_router
        ::CLI::UI::StdoutRouter.enable
      end

      def fmt(text) = ::CLI::UI.fmt(text)
      def frame(title, **opts, &block) = ::CLI::UI::Frame.open(title, timing: false, **opts, &block)

      def success(text) = fmt("{{green:#{text}}}")
      def error(text) = fmt("{{red:#{text}}}")
      def warn(text) = fmt("{{yellow:#{text}}}")
      def accent(text) = fmt("{{cyan:#{text}}}")
      def bold(text) = fmt("{{bold:#{text}}}")
      def italic(text) = fmt("{{italic:#{text}}}")
      def secondary(text) = fmt("{{magenta:#{text}}}")
    end
  end
end
