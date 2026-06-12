# frozen_string_literal: true

require "test_helper"

class Rixie::Tool::FetchTest < Minitest::Test
  SAMPLE_HTML = <<~HTML
    <html>
      <head><title>Test Page</title></head>
      <body>
        <nav>Navigation here</nav>
        <header>Header content</header>
        <main>
          <h1>Main heading</h1>
          <p>Useful paragraph text.</p>
          <pre>some code</pre>
          <script>alert('bad')</script>
          <style>.hidden { display: none }</style>
        </main>
        <footer>Footer content</footer>
      </body>
    </html>
  HTML

  def build_http_client(body:, content_type: "text/html; charset=utf-8")
    res = {
      status: 200,
      headers: {"content-type" => [content_type]},
      body: body
    }
    client = Object.new
    client.define_singleton_method(:get) { |_url| res }
    client
  end

  def with_stubbed_http_client(body:, content_type: "text/html; charset=utf-8")
    fake_client = build_http_client(body: body, content_type: content_type)
    Rixie::Http::Client.stub(:new, fake_client) do
      yield
    end
  end

  def test_fetch_is_a_tool_instance
    assert_instance_of Rixie::Tool, Rixie::Tool::Fetch
  end

  def test_tool_name_is_fetch
    assert_equal "fetch", Rixie::Tool::Fetch.name
  end

  def test_call_returns_sanitized_text_for_html_response
    with_stubbed_http_client(body: SAMPLE_HTML) do
      output = Rixie::Tool::Fetch.call({"url" => "https://example.com"})
      assert_match "Main heading", output
      assert_match "Useful paragraph text.", output
    end
  end

  def test_call_removes_script_tags
    with_stubbed_http_client(body: SAMPLE_HTML) do
      output = Rixie::Tool::Fetch.call({"url" => "https://example.com"})
      refute_match "alert('bad')", output
    end
  end

  def test_call_removes_style_tags
    with_stubbed_http_client(body: SAMPLE_HTML) do
      output = Rixie::Tool::Fetch.call({"url" => "https://example.com"})
      refute_match ".hidden", output
    end
  end

  def test_call_removes_nav_tags
    with_stubbed_http_client(body: SAMPLE_HTML) do
      output = Rixie::Tool::Fetch.call({"url" => "https://example.com"})
      refute_match "Navigation here", output
    end
  end

  def test_call_removes_header_tags
    with_stubbed_http_client(body: SAMPLE_HTML) do
      output = Rixie::Tool::Fetch.call({"url" => "https://example.com"})
      refute_match "Header content", output
    end
  end

  def test_call_removes_footer_tags
    with_stubbed_http_client(body: SAMPLE_HTML) do
      output = Rixie::Tool::Fetch.call({"url" => "https://example.com"})
      refute_match "Footer content", output
    end
  end

  def test_call_replaces_pre_tags_with_placeholder
    with_stubbed_http_client(body: SAMPLE_HTML) do
      output = Rixie::Tool::Fetch.call({"url" => "https://example.com"})
      assert_match "[code block omitted]", output
      refute_match "some code", output
    end
  end

  def test_call_returns_raw_body_for_non_html_content_type
    with_stubbed_http_client(body: '{"key": "value"}', content_type: "application/json") do
      output = Rixie::Tool::Fetch.call({"url" => "https://api.example.com/data"})
      assert_equal '{"key": "value"}', output
    end
  end

  def test_call_raises_ssrf_error_for_blocked_hosts
    assert_raises(Rixie::Http::SSRFError) do
      Rixie::Tool::Fetch.call({"url" => "http://localhost/secret"})
    end
  end

  def test_call_handles_nil_body_gracefully
    with_stubbed_http_client(body: nil) do
      result = Rixie::Tool::Fetch.call({"url" => "https://example.com"})
      assert_kind_of String, result
    end
  end

  def test_call_truncates_html_text_beyond_max_length
    html = "<html><body><p>#{"a" * 100}</p></body></html>"
    with_stubbed_http_client(body: html) do
      output = Rixie::Tool::Fetch.with(max_length: 10).call({"url" => "https://example.com"})
      assert output.start_with?("a" * 10)
      assert_includes output, "[truncated: content exceeded 10 characters]"
      refute_includes output, "a" * 11
    end
  end

  def test_call_truncates_non_html_body_beyond_max_length
    with_stubbed_http_client(body: "b" * 100, content_type: "text/plain") do
      output = Rixie::Tool::Fetch.with(max_length: 10).call({"url" => "https://example.com"})
      assert_includes output, "[truncated: content exceeded 10 characters]"
    end
  end

  def test_call_does_not_truncate_body_within_max_length
    with_stubbed_http_client(body: "short", content_type: "text/plain") do
      output = Rixie::Tool::Fetch.call({"url" => "https://example.com"})
      assert_equal "short", output
    end
  end

  def test_with_returns_a_new_tool_instance
    custom = Rixie::Tool::Fetch.with(max_length: 10)
    assert_instance_of Rixie::Tool, custom
    refute_same Rixie::Tool::Fetch, custom
    assert_equal "fetch", custom.name
  end

  def test_call_collapses_excess_whitespace
    html = "<html><body><p>Line one</p>\n\n\n\n<p>Line two</p></body></html>"
    with_stubbed_http_client(body: html) do
      output = Rixie::Tool::Fetch.call({"url" => "https://example.com"})
      refute_match(/\n{3,}/, output)
    end
  end

  def test_call_strips_leading_trailing_spaces_per_line
    html = "<html><body><p>   spaced   </p></body></html>"
    with_stubbed_http_client(body: html) do
      output = Rixie::Tool::Fetch.call({"url" => "https://example.com"})
      output.each_line { |line| assert_equal line.rstrip, line.rstrip }
      refute_match(/^ +/, output)
    end
  end
end
