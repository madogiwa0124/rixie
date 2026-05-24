# frozen_string_literal: true

module Rixie
  class Tool
    build = ->(language: Search::Wikipedia::DEFAULT_LANGUAGE, max_results: Search::Wikipedia::DEFAULT_MAX_RESULTS) {
      provider = Search::Wikipedia.new(language: language)
      Tool.new(
        name: "wikipedia_search",
        description: "Search Wikipedia for encyclopedic information about people, places, " \
                     "concepts, or events. Returns titles, snippets, and article URLs. " \
                     "Use this when you need authoritative reference information rather " \
                     "than general web results.",
        input_schema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "The search query"
            }
          },
          required: ["query"]
        },
        call: ->(args) {
          results = provider.search(args["query"] || args[:query], max_results: max_results)
          if results.empty?
            "No results found."
          else
            results.map.with_index(1) { |r, i|
              "#{i}. #{r[:title]}\n   #{r[:snippet]}\n   URL: #{r[:url]}"
            }.join("\n\n")
          end
        }
      )
    }
    WikipediaSearch = build.call
    WikipediaSearch.define_singleton_method(:with, &build)
  end
end
