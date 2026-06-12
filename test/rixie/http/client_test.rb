# frozen_string_literal: true

require "test_helper"
require "zlib"
require "stringio"

class Rixie::Http::ClientTest < Minitest::Test
  def build_response(body:, status: "200", headers: {}, content_encoding: nil)
    h = headers.dup
    h["content-encoding"] = [content_encoding] if content_encoding
    res = Object.new
    res.define_singleton_method(:code) { status }
    res.define_singleton_method(:body) { body }
    res.define_singleton_method(:to_hash) { h }
    res.define_singleton_method(:[]) { |key| h[key]&.first }
    res
  end

  def plain_response(body = "hello")
    build_response(body: body)
  end

  def mock_http_for(response)
    http = Object.new
    http.define_singleton_method(:request) { |_req| response }
    http
  end

  def queue_http_for(*responses)
    queue = responses.dup
    http = Object.new
    http.define_singleton_method(:request) { |_req| queue.shift }
    http
  end

  def spy_http(&on_request)
    http = Object.new
    http.define_singleton_method(:request) { |req| on_request.call(req) }
    http
  end

  def build_client(http_client: nil, headers: {})
    Rixie::Http::Client.new(http_client: http_client, headers: headers)
  end

  # --- get ---

  def test_get_returns_hash_with_status_headers_body
    res = plain_response("body text")
    client = build_client(http_client: mock_http_for(res))
    result = client.get("https://example.com/path")
    assert_equal 200, result[:status]
    assert_kind_of Hash, result[:headers]
    assert_equal "body text", result[:body]
  end

  def test_get_sends_default_user_agent_header
    res = plain_response("ok")
    captured_req = nil
    http = spy_http { |req|
      captured_req = req
      res
    }
    client = Rixie::Http::Client.new(http_client: http)
    client.get("https://example.com/")
    assert_equal "Rixie/#{Rixie::VERSION}", captured_req["User-Agent"]
  end

  # --- post ---

  def test_post_returns_hash_with_status_headers_body
    res = plain_response("post body")
    client = build_client(http_client: mock_http_for(res))
    result = client.post("https://example.com/api", body: '{"key":"val"}')
    assert_equal 200, result[:status]
    assert_equal "post body", result[:body]
  end

  def test_post_sends_body_correctly
    res = plain_response("ok")
    captured_req = nil
    http = spy_http { |req|
      captured_req = req
      res
    }
    client = Rixie::Http::Client.new(http_client: http)
    client.post("https://example.com/api", body: '{"x":1}')
    assert_equal '{"x":1}', captured_req.body
  end

  # --- SSRF protection ---

  def test_get_raises_ssrf_error_for_localhost
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("http://localhost/foo") }
  end

  def test_get_raises_ssrf_error_for_127_addresses
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("http://127.0.0.1/foo") }
    assert_raises(Rixie::Http::SSRFError) { client.get("http://127.1.2.3/foo") }
  end

  def test_get_raises_ssrf_error_for_10_addresses
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("http://10.0.0.1/foo") }
  end

  def test_get_raises_ssrf_error_for_192_168_addresses
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("http://192.168.1.1/foo") }
  end

  def test_get_raises_ssrf_error_for_172_16_31_addresses
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("http://172.16.0.1/foo") }
    assert_raises(Rixie::Http::SSRFError) { client.get("http://172.31.255.255/foo") }
  end

  def test_get_raises_ssrf_error_for_zero_address
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("http://0.0.0.0/foo") }
  end

  def test_get_raises_ssrf_error_for_file_scheme
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("file:///etc/passwd") }
  end

  def test_get_raises_ssrf_error_for_ftp_scheme
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("ftp://example.com/file") }
  end

  def test_get_raises_ssrf_error_for_ipv6_loopback
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("http://[::1]/foo") }
  end

  def test_get_raises_ssrf_error_for_ipv6_link_local
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("http://[fe80::1]/foo") }
  end

  def test_get_raises_ssrf_error_for_ipv6_unique_local_fc
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("http://[fc00::1]/foo") }
  end

  def test_get_raises_ssrf_error_for_ipv6_unique_local_fd
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("http://[fd00::1]/foo") }
  end

  def test_get_raises_ssrf_error_for_ipv6_mapped_ipv4
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("http://[::ffff:127.0.0.1]/foo") }
  end

  def test_get_raises_ssrf_error_for_link_local_addresses
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("http://169.254.169.254/latest/meta-data/") }
    assert_raises(Rixie::Http::SSRFError) { client.get("http://169.254.0.1/foo") }
  end

  def test_get_raises_ssrf_error_for_cgnat_addresses
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("http://100.64.0.1/foo") }
    assert_raises(Rixie::Http::SSRFError) { client.get("http://100.127.255.255/foo") }
  end

  def test_get_raises_ssrf_error_for_multicast_and_reserved_addresses
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("http://224.0.0.1/foo") }
    assert_raises(Rixie::Http::SSRFError) { client.get("http://255.255.255.255/foo") }
  end

  def test_get_raises_ssrf_error_for_ipv6_multicast
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("http://[ff02::1]/foo") }
  end

  def test_get_raises_ssrf_error_for_localhost_subdomain
    client = build_client
    assert_raises(Rixie::Http::SSRFError) { client.get("http://sub.localhost/foo") }
  end

  def test_get_allows_public_ip_literal
    res = plain_response("ok")
    client = build_client(http_client: mock_http_for(res))
    result = client.get("http://93.184.216.34/foo")
    assert_equal 200, result[:status]
  end

  def test_get_allows_public_https
    res = plain_response("ok")
    client = build_client(http_client: mock_http_for(res))
    result = client.get("https://example.com/path")
    assert_equal 200, result[:status]
  end

  def test_get_allows_public_http
    res = plain_response("ok")
    client = build_client(http_client: mock_http_for(res))
    result = client.get("http://example.com/path")
    assert_equal 200, result[:status]
  end

  # --- allow_private ---

  def test_allow_private_skips_ssrf_check_for_localhost
    res = plain_response("ok")
    client = Rixie::Http::Client.new(http_client: mock_http_for(res), allow_private: true)
    result = client.get("http://localhost:9000/foo")
    assert_equal 200, result[:status]
  end

  def test_allow_private_skips_ssrf_check_for_127_addresses
    res = plain_response("ok")
    client = Rixie::Http::Client.new(http_client: mock_http_for(res), allow_private: true)
    result = client.post("http://127.0.0.1:8080/api", body: "{}")
    assert_equal 200, result[:status]
  end

  def test_allow_private_still_blocks_unsupported_schemes
    client = Rixie::Http::Client.new(allow_private: true)
    assert_raises(Rixie::Http::SSRFError) { client.get("file:///etc/passwd") }
  end

  def test_allow_private_skips_redirect_ssrf_check
    redirect = build_response(body: "", status: "301", headers: {"location" => ["http://localhost/secret"]})
    final = plain_response("inside")
    client = Rixie::Http::Client.new(http_client: queue_http_for(redirect, final), allow_private: true)
    result = client.get("http://example.com/")
    assert_equal 200, result[:status]
    assert_equal "inside", result[:body]
  end

  # --- error handling ---

  def test_get_raises_timeout_error_on_net_read_timeout
    http = spy_http { |_req| raise Net::ReadTimeout }
    client = build_client(http_client: http)
    assert_raises(Rixie::Http::TimeoutError) { client.get("https://example.com/") }
  end

  def test_get_raises_timeout_error_on_net_open_timeout
    http = spy_http { |_req| raise Net::OpenTimeout }
    client = build_client(http_client: http)
    assert_raises(Rixie::Http::TimeoutError) { client.get("https://example.com/") }
  end

  def test_get_raises_connection_error_on_econnrefused
    http = spy_http { |_req| raise Errno::ECONNREFUSED }
    client = build_client(http_client: http)
    assert_raises(Rixie::Http::ConnectionError) { client.get("https://example.com/") }
  end

  # --- decode_body ---

  def test_decode_body_returns_body_as_is_for_no_encoding
    res = plain_response("plain text")
    client = build_client(http_client: mock_http_for(res))
    result = client.get("https://example.com/")
    assert_equal "plain text", result[:body]
  end

  def test_decode_body_handles_gzip_encoding
    raw = "hello gzip"
    io = StringIO.new
    Zlib::GzipWriter.new(io).tap { |gz|
      gz.write(raw)
      gz.close
    }
    compressed = io.string
    res = build_response(body: compressed, content_encoding: "gzip")
    client = build_client(http_client: mock_http_for(res))
    result = client.get("https://example.com/")
    assert_equal raw, result[:body]
  end

  def test_decode_body_handles_deflate_encoding
    raw = "hello deflate"
    compressed = Zlib::Deflate.deflate(raw)
    res = build_response(body: compressed, content_encoding: "deflate")
    client = build_client(http_client: mock_http_for(res))
    result = client.get("https://example.com/")
    assert_equal raw, result[:body]
  end

  # --- http_client injection ---

  def test_http_client_injection_avoids_real_http
    called = false
    res = plain_response("injected")
    http = spy_http { |_req|
      called = true
      res
    }
    client = Rixie::Http::Client.new(http_client: http)
    result = client.get("https://example.com/")
    assert called
    assert_equal "injected", result[:body]
  end

  # --- redirect following ---

  def test_get_follows_301_redirect
    redirect = build_response(body: "", status: "301", headers: {"location" => ["https://example.com/new"]})
    final = plain_response("final content")
    client = build_client(http_client: queue_http_for(redirect, final))
    result = client.get("https://example.com/old")
    assert_equal 200, result[:status]
    assert_equal "final content", result[:body]
  end

  def test_get_follows_302_redirect
    redirect = build_response(body: "", status: "302", headers: {"location" => ["https://example.com/new"]})
    final = plain_response("ok")
    client = build_client(http_client: queue_http_for(redirect, final))
    result = client.get("https://example.com/")
    assert_equal 200, result[:status]
  end

  def test_get_raises_connection_error_when_too_many_redirects
    redirect = build_response(body: "", status: "301", headers: {"location" => ["https://example.com/loop"]})
    client = build_client(http_client: queue_http_for(*Array.new(10, redirect)))
    assert_raises(Rixie::Http::ConnectionError) { client.get("https://example.com/start") }
  end

  def test_get_follows_relative_path_redirect
    redirect = build_response(body: "", status: "301", headers: {"location" => ["/new-path"]})
    final = plain_response("final")
    client = build_client(http_client: queue_http_for(redirect, final))
    result = client.get("https://example.com/old")
    assert_equal 200, result[:status]
    assert_equal "final", result[:body]
  end

  def test_get_follows_protocol_relative_redirect
    redirect = build_response(body: "", status: "301", headers: {"location" => ["//example.com/new"]})
    final = plain_response("final")
    client = build_client(http_client: queue_http_for(redirect, final))
    result = client.get("https://example.com/old")
    assert_equal 200, result[:status]
  end

  def test_redirect_ssrf_protection
    redirect = build_response(body: "", status: "301", headers: {"location" => ["http://localhost/secret"]})
    client = build_client(http_client: queue_http_for(redirect))
    assert_raises(Rixie::Http::SSRFError) { client.get("https://example.com/") }
  end

  # --- normalize_headers ---

  def test_response_headers_are_normalized_to_lowercase
    res = build_response(body: "ok", headers: {"Content-Type" => ["text/html"]})
    client = build_client(http_client: mock_http_for(res))
    result = client.get("https://example.com/")
    assert result[:headers].key?("content-type"), "expected lowercase content-type key"
    refute result[:headers].key?("Content-Type"), "expected no mixed-case key"
  end

  def test_custom_headers_merged_with_defaults
    res = plain_response("ok")
    captured_req = nil
    http = spy_http { |req|
      captured_req = req
      res
    }
    client = Rixie::Http::Client.new(headers: {"X-Custom" => "value"}, http_client: http)
    client.get("https://example.com/")
    assert_equal "value", captured_req["X-Custom"]
    assert_equal "Rixie/#{Rixie::VERSION}", captured_req["User-Agent"]
  end
end
