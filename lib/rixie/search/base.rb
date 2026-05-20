# frozen_string_literal: true

module Rixie
  module Search
    # Interface for search providers.
    # Implementations must return Array<Hash> with keys: title, snippet, url.
    class Base
      def search(query, max_results:)
        raise Rixie::NotImplementedError, "#{self.class}#search not implemented"
      end
    end
  end
end
