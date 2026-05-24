# frozen_string_literal: true

require "json"
require "uri"

module Rixie
  module Search
    class Wikipedia < Base
      DEFAULT_MAX_RESULTS = 5
      DEFAULT_LANGUAGE = "en"

      def initialize(language: DEFAULT_LANGUAGE, http_client: nil)
        @language = language
        @http_client = Rixie::Http::Client.new(
          headers: {"Accept" => "application/json"},
          http_client: http_client
        )
      end

      def search(query, max_results: DEFAULT_MAX_RESULTS)
        response = @http_client.get(build_url(query, max_results))
        data = JSON.parse(response[:body].to_s)
        Array(data.dig("query", "search")).map { |hit| format_result(hit) }
      rescue JSON::ParserError
        []
      end

      private

      def build_url(query, max_results)
        params = URI.encode_www_form(
          action: "query",
          list: "search",
          srsearch: query,
          srlimit: max_results,
          format: "json",
          formatversion: 2
        )
        "https://#{@language}.wikipedia.org/w/api.php?#{params}"
      end

      def format_result(hit)
        title = hit["title"].to_s
        {
          title: title,
          snippet: strip_html(hit["snippet"].to_s),
          url: "https://#{@language}.wikipedia.org/wiki/#{URI.encode_www_form_component(title.tr(" ", "_"))}"
        }
      end

      ENTITIES = {"&quot;" => '"', "&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&#39;" => "'", "&nbsp;" => " "}.freeze
      private_constant :ENTITIES

      def strip_html(text)
        text.gsub(/<[^>]+>/, "").gsub(/&\w+;|&#\d+;/) { |e| ENTITIES[e] || e }.strip
      end
    end
  end
end
