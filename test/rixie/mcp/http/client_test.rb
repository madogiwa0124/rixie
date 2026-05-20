# frozen_string_literal: true

require "test_helper"

class Rixie::MCP::Http::ClientTest < Minitest::Test
  def setup
    super
    @url = "http://example.com/mcp"
  end

  # --- helpers ---

  # Builds a fake Net::HTTP instance whose #request returns JSON bodies in order.
  def mock_net_http(*response_bodies)
    queue = response_bodies.dup
    http = Object.new
    http.define_singleton_method(:request) do |_req|
      body_hash = queue.shift
      json = JSON.generate(body_hash)
      res = Object.new
      res.define_singleton_method(:code) { "200" }
      res.define_singleton_method(:body) { json }
      res.define_singleton_method(:to_hash) { {} }
      res.define_singleton_method(:[]) { |_key| nil }
      res
    end
    http
  end

  # Builds a spy Net::HTTP instance that calls the block for each #request.
  # Block receives the Net::HTTP::Request object and must return a response.
  def spy_net_http(&on_request)
    http = Object.new
    http.define_singleton_method(:request) { |req| on_request.call(req) }
    http
  end

  def json_net_response(body_hash)
    json = JSON.generate(body_hash)
    res = Object.new
    res.define_singleton_method(:code) { "200" }
    res.define_singleton_method(:body) { json }
    res.define_singleton_method(:to_hash) { {} }
    res.define_singleton_method(:[]) { |_key| nil }
    res
  end

  def new_client(responses: nil, headers: {}, initialized: false, **opts)
    opts[:http_client] = mock_net_http(*responses) if responses
    Rixie::MCP::Http::Client.new(url: @url, headers: headers, **opts).tap do |c|
      c.instance_variable_set(:@session_initialized, true) if initialized
    end
  end

  def new_client_spy(headers: {}, initialized: false, client_info: nil, &on_request)
    http = spy_net_http(&on_request)
    Rixie::MCP::Http::Client.new(url: @url, headers: headers, client_info: client_info, http_client: http).tap do |c|
      c.instance_variable_set(:@session_initialized, true) if initialized
    end
  end

  def dispatch_response(parsed)
    case parsed["method"]
    when "initialize"
      json_net_response({"jsonrpc" => "2.0", "id" => parsed["id"], "result" => {}})
    when "tools/list"
      json_net_response({"jsonrpc" => "2.0", "id" => parsed["id"], "result" => {"tools" => []}})
    when "tools/call"
      json_net_response({"jsonrpc" => "2.0", "id" => parsed["id"], "result" => {"content" => [{"type" => "text", "text" => "ok"}]}})
    end
  end

  def init_response
    {"jsonrpc" => "2.0", "id" => 1, "result" => {}}
  end

  def tools_response(tools)
    {"jsonrpc" => "2.0", "id" => 2, "result" => {"tools" => tools}}
  end

  def call_tool_response(texts)
    content = texts.map { |t| {"type" => "text", "text" => t} }
    {"jsonrpc" => "2.0", "id" => 2, "result" => {"content" => content}}
  end

  def sample_tool_def
    {
      "name" => "get_weather",
      "description" => "Get current weather",
      "inputSchema" => {
        "type" => "object",
        "properties" => {"location" => {"type" => "string"}},
        "required" => ["location"]
      }
    }
  end

  # --- tools ---

  def test_tools_returns_array_of_rixie_tool
    client = new_client(responses: [init_response, tools_response([sample_tool_def])])
    result = client.tools
    assert_kind_of Array, result
    assert_equal 1, result.size
    assert_kind_of Rixie::Tool, result.first
  end

  def test_tools_maps_name_and_description
    client = new_client(responses: [init_response, tools_response([sample_tool_def])])
    tool = client.tools.first
    assert_equal "get_weather", tool.name
    assert_equal "Get current weather", tool.description
  end

  def test_tools_maps_input_schema_from_camel_case
    client = new_client(responses: [init_response, tools_response([sample_tool_def])])
    tool = client.tools.first
    assert_equal sample_tool_def["inputSchema"], tool.input_schema
  end

  def test_tools_call_lambda_invokes_call_tool
    client = new_client(responses: [
      init_response,
      tools_response([sample_tool_def]),
      call_tool_response(["sunny"])
    ])
    tool = client.tools.first
    assert_equal "sunny", tool.call({"location" => "Tokyo"})
  end

  # --- list_tools ---

  def test_list_tools_sends_tools_list_request
    captured = nil
    new_client_spy { |req|
      parsed = JSON.parse(req.body)
      captured = parsed
      dispatch_response(parsed)
    }.list_tools
    assert_equal "tools/list", captured["method"]
  end

  def test_list_tools_calls_initialize_session_before_request
    requests = []
    new_client_spy { |req|
      parsed = JSON.parse(req.body)
      requests << parsed["method"]
      dispatch_response(parsed)
    }.list_tools
    assert_equal ["initialize", "tools/list"], requests
  end

  def test_list_tools_returns_empty_array_when_no_tools_key
    client = new_client(responses: [init_response, {"jsonrpc" => "2.0", "id" => 2, "result" => {}}])
    assert_equal [], client.list_tools
  end

  # --- call_tool ---

  def test_call_tool_sends_tools_call_request
    captured = nil
    new_client_spy { |req|
      parsed = JSON.parse(req.body)
      captured = parsed
      dispatch_response(parsed)
    }.call_tool("my_tool", {"x" => 1})
    assert_equal "tools/call", captured["method"]
    assert_equal "my_tool", captured["params"]["name"]
    assert_equal({"x" => 1}, captured["params"]["arguments"])
  end

  def test_call_tool_joins_multiple_content_blocks
    client = new_client(responses: [init_response, call_tool_response(["hello", " ", "world"])])
    assert_equal "hello world", client.call_tool("say_hi")
  end

  def test_call_tool_calls_initialize_session_before_request
    requests = []
    new_client_spy { |req|
      parsed = JSON.parse(req.body)
      requests << parsed["method"]
      dispatch_response(parsed)
    }.call_tool("my_tool")
    assert_equal ["initialize", "tools/call"], requests
  end

  # --- initialize_session ---

  def test_initialize_session_sends_initialize_only_once
    call_count = 0
    client = new_client_spy { |req|
      parsed = JSON.parse(req.body)
      call_count += 1 if parsed["method"] == "initialize"
      dispatch_response(parsed)
    }
    client.list_tools
    client.list_tools
    assert_equal 1, call_count
  end

  def test_initialize_session_sends_correct_protocol_version_and_client_info
    captured_params = nil
    new_client_spy { |req|
      parsed = JSON.parse(req.body)
      captured_params = parsed["params"] if parsed["method"] == "initialize"
      dispatch_response(parsed)
    }.list_tools
    assert_equal Rixie::MCP::Http::Client::MCP_PROTOCOL_VERSION, captured_params["protocolVersion"]
    assert_equal "rixie", captured_params["clientInfo"]["name"]
    assert_equal Rixie::VERSION, captured_params["clientInfo"]["version"]
  end

  def test_custom_client_info_is_sent_in_initialize
    captured_params = nil
    new_client_spy(client_info: {name: "my-app", version: "2.0.0"}) { |req|
      parsed = JSON.parse(req.body)
      captured_params = parsed["params"] if parsed["method"] == "initialize"
      dispatch_response(parsed)
    }.list_tools
    assert_equal "my-app", captured_params["clientInfo"]["name"]
    assert_equal "2.0.0", captured_params["clientInfo"]["version"]
  end

  # --- request error handling ---

  def test_request_raises_protocol_error_on_error_key
    error_body = {"jsonrpc" => "2.0", "id" => 1, "error" => {"code" => -32600, "message" => "Invalid Request"}}
    client = new_client(responses: [error_body], initialized: true)
    err = assert_raises(Rixie::MCP::ProtocolError) { client.list_tools }
    assert_equal "Invalid Request", err.message
  end

  def test_request_raises_timeout_error_on_read_timeout
    http = spy_net_http { |_req| raise Net::ReadTimeout }
    client = Rixie::MCP::Http::Client.new(url: @url, http_client: http).tap do |c|
      c.instance_variable_set(:@session_initialized, true)
    end
    assert_raises(Rixie::MCP::TimeoutError) { client.list_tools }
  end

  def test_request_raises_timeout_error_on_open_timeout
    http = spy_net_http { |_req| raise Net::OpenTimeout }
    client = Rixie::MCP::Http::Client.new(url: @url, http_client: http).tap do |c|
      c.instance_variable_set(:@session_initialized, true)
    end
    assert_raises(Rixie::MCP::TimeoutError) { client.list_tools }
  end

  def test_http_error_is_mapped_to_mcp_request_error
    http = spy_net_http { |_req| raise Errno::ECONNREFUSED }
    client = Rixie::MCP::Http::Client.new(url: @url, http_client: http).tap do |c|
      c.instance_variable_set(:@session_initialized, true)
    end
    assert_raises(Rixie::MCP::RequestError) { client.list_tools }
  end

  # --- custom headers ---

  def test_custom_headers_included_in_every_request
    seen_auth = []
    new_client_spy(headers: {"Authorization" => "Bearer secret"}) { |req|
      seen_auth << req["Authorization"]
      dispatch_response(JSON.parse(req.body))
    }.list_tools
    assert_equal ["Bearer secret", "Bearer secret"], seen_auth
  end
end
