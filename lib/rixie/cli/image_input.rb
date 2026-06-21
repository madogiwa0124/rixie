# frozen_string_literal: true

require "base64"

module Rixie
  class CLI
    # Parses a line of CLI text into the value passed to `Session#live`.
    #
    # Plain text is returned as a `String` unchanged. A whitespace-separated
    # token of the form `@<path>` that points at an existing image file is
    # converted into a Rixie image content block; when at least one such token
    # is present the result becomes an `Array` of content blocks (the remaining
    # text first, then each image). A `@<path>` token that does not resolve to a
    # readable image file is left untouched as literal text — this keeps stray
    # "@" characters (e.g. in prose) from being silently dropped.
    #
    # Pure function module: it only reads the filesystem to load referenced
    # images. Reading/encoding is intentionally done here (CLI's responsibility)
    # so the rest of the stack keeps receiving plain `String | Array<Hash>`.
    module ImageInput
      MEDIA_TYPES = {
        ".png" => "image/png",
        ".jpg" => "image/jpeg",
        ".jpeg" => "image/jpeg",
        ".gif" => "image/gif",
        ".webp" => "image/webp"
      }.freeze

      module_function

      def parse(input)
        tokens = input.split(/\s+/)
        image_tokens = tokens.select { |t| image_token?(t) }
        return input if image_tokens.empty?

        blocks = []
        text = (tokens - image_tokens).join(" ").strip
        blocks << {type: "text", text: text} unless text.empty?
        image_tokens.each { |t| blocks << image_block(t.delete_prefix("@")) }
        blocks
      end

      def image_token?(token)
        return false unless token.start_with?("@")

        path = File.expand_path(token.delete_prefix("@"))
        MEDIA_TYPES.key?(File.extname(path).downcase) && File.file?(path) && File.readable?(path)
      end

      def image_block(path)
        full = File.expand_path(path)
        {
          type: "image",
          source: {
            type: "base64",
            media_type: MEDIA_TYPES.fetch(File.extname(full).downcase),
            data: Base64.strict_encode64(File.binread(full))
          }
        }
      rescue SystemCallError => e
        # image_token? already vetted the file, but it can vanish or lose read
        # permission between the check and the read. Surface a Rixie::Error so the
        # CLI renders it via agent_error instead of crashing the REPL.
        raise Rixie::Error, "Could not read image file #{path}: #{e.message}"
      end
    end
  end
end
