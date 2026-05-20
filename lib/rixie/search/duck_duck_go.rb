# frozen_string_literal: true

require "nokogiri"
require "uri"

module Rixie
  module Search
    class DuckDuckGo < Base
      SEARCH_URL = "https://lite.duckduckgo.com/lite/"
      DEFAULT_MAX_RESULTS = 5

      def initialize(http_client: nil)
        @http_client = Rixie::Http::Client.new(
          headers: {
            "Accept" => "text/html",
            "Accept-Language" => "en-US,en;q=0.9"
          },
          http_client: http_client
        )
      end

      def search(query, max_results: DEFAULT_MAX_RESULTS)
        url = "#{SEARCH_URL}?q=#{URI.encode_www_form_component(query)}"
        response = @http_client.get(url)
        doc = Nokogiri::HTML(response[:body])
        parse_results(doc, max_results)
      end

      private

      def parse_results(doc, max_results)
        results = []
        doc.css("a.result-link").each do |a|
          url = extract_url(a["href"].to_s)
          next unless url

          title = a.text.strip
          next if title.empty?

          snippet_td = a.ancestors("tr").first&.next_element&.css("td.result-snippet")&.first
          snippet = snippet_td&.text&.strip.to_s

          results << {title: title, url: url, snippet: snippet}
          break if results.size >= max_results
        end
        results
      rescue
        []
      end

      def extract_url(href)
        return nil unless href.to_s.start_with?("//")

        uddg = URI.decode_www_form(URI.parse("https:#{href}").query.to_s).to_h["uddg"]
        uddg if uddg&.match?(/\Ahttps?:\/\//)
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
