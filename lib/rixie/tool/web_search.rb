# frozen_string_literal: true

module Rixie
  class Tool
    build = ->(provider: Search::DuckDuckGo.new, max_results: 5) {
      Tool.new(
        name: "web_search",
        description: "Search the web for current information. Returns a list of relevant results with titles, snippets, and URLs.",
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
          results = provider.search(args["query"], max_results: max_results)
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
    WebSearch = build.call
    WebSearch.define_singleton_method(:with, &build)
  end
end
