# frozen_string_literal: true

require_relative "image_input"

module Rixie
  class CLI
    # Tab completion for `@<path>` image tokens typed at the CLI prompt.
    #
    # The completion proc runs with `Reline.completer_word_break_characters = ""`,
    # so `complete` receives the whole line up to the cursor and must return
    # full-line replacement candidates — the same contract the slash-command
    # completions follow. It only activates when the line ends with an unfinished
    # `@<path>` token; otherwise it returns `[]` so the prompt offers no completion.
    #
    # Candidates are directories (always, so the user can navigate into them) and
    # image files whose extension `ImageInput` recognizes — guiding the user toward
    # valid attachments. Directory candidates get a trailing "/" so a second Tab
    # descends into them.
    #
    # Pure function module: it only reads the filesystem to list candidate paths.
    module PathCompletion
      module_function

      def complete(line)
        match = line.match(/(?:\A|\s)@(\S*)\z/)
        return [] unless match

        partial = match[1]
        prefix = line[0, line.length - partial.length] # everything up to and including "@"
        tokens(partial).map { |token| prefix + token }
      end

      def tokens(partial)
        slash = partial.rindex("/")
        dir_typed = slash ? partial[0..slash] : ""
        frag = slash ? partial[(slash + 1)..] : partial
        search_dir = File.expand_path(dir_typed.empty? ? "." : dir_typed)
        return [] unless File.directory?(search_dir)

        entries(search_dir, frag).map do |entry|
          suffix = File.directory?(File.join(search_dir, entry)) ? "/" : ""
          "#{dir_typed}#{entry}#{suffix}"
        end
      end

      def entries(search_dir, frag)
        Dir.children(search_dir).select { |entry|
          next false if frag.empty? && entry.start_with?(".") # hide dotfiles unless asked for
          next false unless entry.start_with?(frag)

          full = File.join(search_dir, entry)
          File.directory?(full) || image_file?(entry)
        }.sort
      rescue SystemCallError
        [] # unreadable directory — offer nothing rather than crash the prompt
      end

      def image_file?(name)
        ImageInput::MEDIA_TYPES.key?(File.extname(name).downcase)
      end
    end
  end
end
