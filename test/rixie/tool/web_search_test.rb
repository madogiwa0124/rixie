# frozen_string_literal: true

require "test_helper"

class Rixie::Tool::WebSearchTest < Minitest::Test
  class FakeProvider
    def initialize(results = [])
      @results = results
      @last_query = nil
      @last_max_results = nil
    end

    attr_reader :last_query, :last_max_results

    def search(query, max_results:)
      @last_query = query
      @last_max_results = max_results
      @results
    end
  end

  def sample_results
    [
      {title: "First Result", snippet: "A useful snippet.", url: "https://first.com"},
      {title: "Second Result", snippet: "Another snippet.", url: "https://second.com"}
    ]
  end

  def test_web_search_is_a_tool_instance
    assert_instance_of Rixie::Tool, Rixie::Tool::WebSearch
  end

  def test_tool_name_is_web_search
    assert_equal "web_search", Rixie::Tool::WebSearch.name
  end

  def test_with_returns_a_tool_instance
    tool = Rixie::Tool::WebSearch.with(provider: FakeProvider.new)
    assert_instance_of Rixie::Tool, tool
  end

  def test_with_returns_a_different_instance_from_default
    tool = Rixie::Tool::WebSearch.with(provider: FakeProvider.new)
    refute_same Rixie::Tool::WebSearch, tool
  end

  def test_with_formats_results_as_numbered_list
    provider = FakeProvider.new(sample_results)
    tool = Rixie::Tool::WebSearch.with(provider: provider)
    output = tool.call({"query" => "ruby"})
    assert_match "1. First Result", output
    assert_match "A useful snippet.", output
    assert_match "URL: https://first.com", output
    assert_match "2. Second Result", output
    assert_match "URL: https://second.com", output
  end

  def test_with_returns_no_results_message_when_empty
    provider = FakeProvider.new([])
    tool = Rixie::Tool::WebSearch.with(provider: provider)
    assert_equal "No results found.", tool.call({"query" => "xyzzy"})
  end

  def test_with_accepts_max_results_configuration
    provider = FakeProvider.new(sample_results)
    tool = Rixie::Tool::WebSearch.with(provider: provider, max_results: 3)
    tool.call({"query" => "test"})
    assert_equal 3, provider.last_max_results
  end

  def test_default_max_results_is_five
    provider = FakeProvider.new([])
    tool = Rixie::Tool::WebSearch.with(provider: provider)
    tool.call({"query" => "test"})
    assert_equal 5, provider.last_max_results
  end

  def test_passes_query_to_provider
    provider = FakeProvider.new([])
    tool = Rixie::Tool::WebSearch.with(provider: provider)
    tool.call({"query" => "ruby on rails"})
    assert_equal "ruby on rails", provider.last_query
  end
end
