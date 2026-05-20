# frozen_string_literal: true

require "nokogiri"

module Rixie
  class Tool
    Fetch = Tool.new(
      name: "fetch",
      description: "Fetch the content of a URL and return the readable text. Useful for reading web pages found via web_search.",
      input_schema: {
        type: "object",
        properties: {
          url: {
            type: "string",
            description: "The URL to fetch"
          }
        },
        required: ["url"]
      },
      call: ->(args) {
        url = args["url"] || args[:url]
        response = Rixie::Http::Client.new.get(url)
        content_type = response[:headers]["content-type"]&.first.to_s

        next response[:body] unless content_type.include?("text/html")

        doc = Nokogiri::HTML(response[:body].to_s)
        doc.css("nav, script, style, footer, header, aside, img, link, figure, blockquote, button, noscript, iframe").remove
        doc.css("pre").each { |pre| pre.replace("[code block omitted]") }
        doc.css("body").text
          .gsub(/[^\S\n]+/, " ")
          .gsub(/^ +| +$/, "")
          .gsub(/\n{3,}/, "\n\n")
          .strip
      }
    )
  end
end
