# frozen_string_literal: true

module Rixie
  class Tool
    build = ->(max_length: 50_000) {
      Tool.new(
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
          begin
            require "nokogiri"
          rescue LoadError
            raise Rixie::ConfigurationError, "nokogiri gem is required for Tool::Fetch. Add `gem 'nokogiri'` to your Gemfile."
          end

          url = args["url"] || args[:url]
          response = Rixie::Http::Client.new.get(url)
          content_type = response[:headers]["content-type"]&.first.to_s

          text = if content_type.include?("text/html")
            doc = Nokogiri::HTML(response[:body].to_s)
            doc.css("nav, script, style, footer, header, aside, img, link, figure, blockquote, button, noscript, iframe").remove
            doc.css("pre").each { |pre| pre.replace("[code block omitted]") }
            doc.css("body").text
              .gsub(/[^\S\n]+/, " ")
              .gsub(/^ +| +$/, "")
              .gsub(/\n{3,}/, "\n\n")
              .strip
          else
            response[:body].to_s
          end

          if text.length > max_length
            text = "#{text[0, max_length]}\n... [truncated: content exceeded #{max_length} characters]"
          end
          text
        }
      )
    }
    Fetch = build.call
    Fetch.define_singleton_method(:with, &build)
  end
end
