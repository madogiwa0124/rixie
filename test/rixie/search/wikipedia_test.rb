# frozen_string_literal: true

require "test_helper"
require "json"

class Rixie::Search::WikipediaTest < Minitest::Test
  SAMPLE_BODY = JSON.dump(
    "query" => {
      "search" => [
        {"title" => "Ruby (programming language)", "snippet" => "<span class=\"searchmatch\">Ruby</span> is a dynamic, interpreted &quot;general-purpose&quot; language."},
        {"title" => "Ruby on Rails", "snippet" => "A server-side web app framework written in Ruby."}
      ]
    }
  )

  EMPTY_BODY = JSON.dump("query" => {"search" => []})

  def build_http_response(body)
    res = Object.new
    res.define_singleton_method(:code) { "200" }
    res.define_singleton_method(:body) { body }
    res.define_singleton_method(:to_hash) { {} }
    res.define_singleton_method(:[]) { |_key| nil }
    res
  end

  def mock_http(body)
    res = build_http_response(body)
    http = Object.new
    http.define_singleton_method(:request) { |_req| res }
    http
  end

  def build_searcher(body = SAMPLE_BODY, language: "en")
    Rixie::Search::Wikipedia.new(language: language, http_client: mock_http(body))
  end

  def test_returns_array_of_hashes
    results = build_searcher.search("ruby")
    assert_kind_of Array, results
    results.each do |r|
      assert r.key?(:title)
      assert r.key?(:snippet)
      assert r.key?(:url)
    end
  end

  def test_extracts_title
    results = build_searcher.search("ruby")
    assert_equal "Ruby (programming language)", results.first[:title]
  end

  def test_strips_html_from_snippet
    results = build_searcher.search("ruby")
    refute_match(/<span/, results.first[:snippet])
    assert_match "Ruby is a dynamic", results.first[:snippet]
  end

  def test_decodes_html_entities_in_snippet
    results = build_searcher.search("ruby")
    assert_match '"general-purpose"', results.first[:snippet]
    refute_match "&quot;", results.first[:snippet]
  end

  def test_builds_article_url_from_title
    results = build_searcher.search("ruby")
    assert_equal "https://en.wikipedia.org/wiki/Ruby_%28programming_language%29", results.first[:url]
  end

  def test_uses_language_in_url
    results = build_searcher(language: "ja").search("ruby")
    assert_match "https://ja.wikipedia.org/wiki/", results.first[:url]
  end

  def test_returns_empty_array_when_no_results
    assert_equal [], build_searcher(EMPTY_BODY).search("xyzzy")
  end

  def test_returns_empty_array_on_invalid_json
    assert_equal [], build_searcher("not json").search("anything")
  end

  def test_passes_query_and_limit_to_api
    captured_req = nil
    res = build_http_response(SAMPLE_BODY)
    http = Object.new
    http.define_singleton_method(:request) { |req|
      captured_req = req
      res
    }
    Rixie::Search::Wikipedia.new(http_client: http).search("ruby on rails", max_results: 3)
    assert_match "srsearch=ruby+on+rails", captured_req.path
    assert_match "srlimit=3", captured_req.path
  end
end
