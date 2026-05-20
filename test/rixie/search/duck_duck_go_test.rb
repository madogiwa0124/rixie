# frozen_string_literal: true

require "test_helper"

class Rixie::Search::DuckDuckGoTest < Minitest::Test
  def ddg_result(n, url:, title:, snippet:)
    encoded = URI.encode_www_form_component(url)
    <<~HTML
      <tr>
        <td valign="top">#{n}.</td>
        <td><a class="result-link" href="//duckduckgo.com/l/?uddg=#{encoded}&rut=abc">#{title}</a></td>
      </tr>
      <tr>
        <td>   </td>
        <td class="result-snippet">#{snippet}</td>
      </tr>
    HTML
  end

  SAMPLE_HTML = <<~HTML
    <html><body><table border="0">
      #{
        [
          {url: "https://example.com", title: "Example Title", snippet: "Example snippet text."},
          {url: "https://another.org/page", title: "Another Result", snippet: "Another snippet here."},
          {url: "https://third.net/", title: "Third Result", snippet: "Third snippet."}
        ].map.with_index(1) { |r, i| "<!-- result #{i} -->" }.join
      }
    </table></body></html>
  HTML

  def sample_html
    rows = [
      {url: "https://example.com", title: "Example Title", snippet: "Example snippet text."},
      {url: "https://another.org/page", title: "Another Result", snippet: "Another snippet here."},
      {url: "https://third.net/", title: "Third Result", snippet: "Third snippet."}
    ].map.with_index(1) { |r, i| ddg_result(i, **r) }.join
    "<html><body><table border=\"0\">#{rows}</table></body></html>"
  end

  EMPTY_HTML = "<html><body><p>No results</p></body></html>"

  def build_http_response(body)
    res = Object.new
    res.define_singleton_method(:code) { "200" }
    res.define_singleton_method(:body) { body }
    res.define_singleton_method(:to_hash) { {} }
    res.define_singleton_method(:[]) { |_key| nil }
    res
  end

  def mock_net_http(body)
    res = build_http_response(body)
    http = Object.new
    http.define_singleton_method(:request) { |_req| res }
    http
  end

  def build_searcher(html = nil)
    Rixie::Search::DuckDuckGo.new(http_client: mock_net_http(html || sample_html))
  end

  def test_search_returns_array_of_hashes
    results = build_searcher.search("ruby")
    assert_kind_of Array, results
    results.each do |r|
      assert r.key?(:title), "missing :title key"
      assert r.key?(:snippet), "missing :snippet key"
      assert r.key?(:url), "missing :url key"
    end
  end

  def test_search_extracts_title_and_url
    results = build_searcher.search("ruby")
    first = results.first
    assert_equal "Example Title", first[:title]
    assert_equal "https://example.com", first[:url]
  end

  def test_search_extracts_snippet
    results = build_searcher.search("ruby")
    assert_equal "Example snippet text.", results.first[:snippet]
  end

  def test_search_limits_results_to_max_results
    results = build_searcher.search("ruby", max_results: 2)
    assert_equal 2, results.size
  end

  def test_search_returns_empty_array_when_no_results
    results = build_searcher(EMPTY_HTML).search("xyzzy no results")
    assert_equal [], results
  end

  def test_search_returns_empty_array_when_parsing_fails
    bad_res = Object.new
    bad_res.define_singleton_method(:code) { "200" }
    bad_res.define_singleton_method(:body) { nil }
    bad_res.define_singleton_method(:to_hash) { {} }
    bad_res.define_singleton_method(:[]) { |_key| nil }
    bad_http = Object.new
    bad_http.define_singleton_method(:request) { |_req| bad_res }
    assert_equal [], Rixie::Search::DuckDuckGo.new(http_client: bad_http).search("test")
  end

  def test_search_uses_correct_url
    captured_req = nil
    res = build_http_response(sample_html)
    http = Object.new
    http.define_singleton_method(:request) { |req|
      captured_req = req
      res
    }
    Rixie::Search::DuckDuckGo.new(http_client: http).search("ruby on rails")
    assert_match "ruby+on+rails", captured_req.path
  end
end
