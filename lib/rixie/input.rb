# frozen_string_literal: true

module Rixie
  # Normalizes and validates the `user_input` passed to `Session#chat` / `#live`.
  #
  # A plain String is the 99% path and is returned unchanged. An Array carries
  # Rixie unified content blocks (multimodal input); each block is validated and
  # rebuilt into a canonical **string-keyed** Hash so every downstream consumer —
  # the adapter (pure wire translation), the JSON-backed stores, and context
  # replay — sees a single representation. Callers may pass symbol or string keys
  # (e.g. CLI-built blocks vs. blocks round-tripped through a JSON store); both
  # are accepted and canonicalized to string keys here.
  #
  # Validation lives at this input boundary, NOT in the adapter (see
  # .claude/rules/adapter.md): "which content types Rixie supports" is domain
  # knowledge, so centralizing it means a new adapter never re-implements these
  # checks. Once normalized, a block the adapter still cannot map is an
  # internal-invariant violation, not user input.
  #
  # Malformed content raises Rixie::InvalidContentError — a terminal caller-input
  # error, distinct from the possibly-transient Rixie::LLM::Error.
  module Input
    module_function

    def normalize(user_input)
      return user_input unless user_input.is_a?(Array)

      user_input.map { |block| normalize_block(block) }
    end

    def normalize_block(block)
      unless block.is_a?(Hash)
        raise Rixie::InvalidContentError, "Invalid content block: expected a Hash, got #{block.inspect}."
      end

      case fetch(block, :type).to_s
      when "text" then normalize_text(block)
      when "image" then normalize_image(block)
      else
        raise Rixie::InvalidContentError,
          "Unknown content block type: #{fetch(block, :type).inspect}. Expected \"text\" or \"image\"."
      end
    end

    # Validated uniformly with the image branch: a text block must carry a String
    # `text` (an earlier asymmetry let `{type:"text"}` slip through as nil text).
    def normalize_text(block)
      text = fetch(block, :text)
      unless text.is_a?(String)
        raise Rixie::InvalidContentError,
          "Invalid text content block: expected a String `text`, got #{text.inspect}."
      end

      {"type" => "text", "text" => text}
    end

    # Only base64 image sources are supported. Reject anything else (missing
    # fields, or the out-of-scope `source.type: "url"` form) so the adapter never
    # has to emit a degenerate `data:;base64,` URI.
    def normalize_image(block)
      source = fetch(block, :source)
      unless source.is_a?(Hash)
        raise Rixie::InvalidContentError, "Invalid image source: expected a Hash, got #{source.inspect}."
      end

      media_type = fetch(source, :media_type).to_s
      data = fetch(source, :data).to_s
      unless fetch(source, :type).to_s == "base64" && !media_type.empty? && !data.empty?
        raise Rixie::InvalidContentError,
          "Invalid image content block: expected source { type: \"base64\", media_type:, data: }, got #{source.inspect}."
      end

      {"type" => "image", "source" => {"type" => "base64", "media_type" => media_type, "data" => data}}
    end

    def fetch(hash, key)
      hash[key] || hash[key.to_s]
    end
  end
end
