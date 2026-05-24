# frozen_string_literal: true

require "test_helper"

class Rixie::Tool::WikipediaSearchTest < Minitest::Test
  class FakeProvider
    attr_reader :last_query, :last_max_results

    def initialize(results = [])
      @results = results
    end

    def search(query, max_results:)
      @last_query = query
      @last_max_results = max_results
      @results
    end
  end

  def sample_results
    [
      {title: "Ruby", snippet: "A programming language.", url: "https://en.wikipedia.org/wiki/Ruby"},
      {title: "Ruby on Rails", snippet: "A web framework.", url: "https://en.wikipedia.org/wiki/Ruby_on_Rails"}
    ]
  end

  def with_stubbed_provider(provider)
    Rixie::Search::Wikipedia.stub(:new, ->(**) { provider }) do
      yield
    end
  end

  def test_is_a_tool_instance
    assert_instance_of Rixie::Tool, Rixie::Tool::WikipediaSearch
  end

  def test_tool_name_is_wikipedia_search
    assert_equal "wikipedia_search", Rixie::Tool::WikipediaSearch.name
  end

  def test_with_returns_a_tool_instance
    with_stubbed_provider(FakeProvider.new) do
      assert_instance_of Rixie::Tool, Rixie::Tool::WikipediaSearch.with
    end
  end

  def test_with_returns_a_different_instance_from_default
    with_stubbed_provider(FakeProvider.new) do
      refute_same Rixie::Tool::WikipediaSearch, Rixie::Tool::WikipediaSearch.with
    end
  end

  def test_formats_results_as_numbered_list
    provider = FakeProvider.new(sample_results)
    with_stubbed_provider(provider) do
      output = Rixie::Tool::WikipediaSearch.with.call({"query" => "ruby"})
      assert_match "1. Ruby", output
      assert_match "A programming language.", output
      assert_match "URL: https://en.wikipedia.org/wiki/Ruby", output
      assert_match "2. Ruby on Rails", output
    end
  end

  def test_returns_no_results_message_when_empty
    with_stubbed_provider(FakeProvider.new([])) do
      assert_equal "No results found.", Rixie::Tool::WikipediaSearch.with.call({"query" => "xyzzy"})
    end
  end

  def test_passes_max_results_to_provider
    provider = FakeProvider.new(sample_results)
    with_stubbed_provider(provider) do
      Rixie::Tool::WikipediaSearch.with(max_results: 3).call({"query" => "test"})
      assert_equal 3, provider.last_max_results
    end
  end

  def test_default_max_results_is_five
    provider = FakeProvider.new([])
    with_stubbed_provider(provider) do
      Rixie::Tool::WikipediaSearch.with.call({"query" => "test"})
      assert_equal 5, provider.last_max_results
    end
  end

  def test_passes_query_to_provider
    provider = FakeProvider.new([])
    with_stubbed_provider(provider) do
      Rixie::Tool::WikipediaSearch.with.call({"query" => "ruby on rails"})
      assert_equal "ruby on rails", provider.last_query
    end
  end
end
