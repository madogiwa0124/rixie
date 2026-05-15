# frozen_string_literal: true

require_relative "test_helper"

# Scenario: agent that uses tools fetched from an MCP HTTP server.
# Verifies that MCP::Http::Client fetches tools and wires them into Session
# end-to-end using a stubbed HTTP server.
class MCPTest < Integration::TestCase
  # A minimal in-process MCP server stub that handles JSON-RPC requests.
  class StubMCPServer
    TOOLS = [
      {
        "name" => "get_time",
        "description" => "Returns the current time for a given timezone.",
        "inputSchema" => {
          "type" => "object",
          "properties" => {"timezone" => {"type" => "string"}},
          "required" => ["timezone"]
        }
      }
    ].freeze

    def call(method, params)
      case method
      when "initialize"
        {"result" => {"protocolVersion" => "2024-11-05", "capabilities" => {}}}
      when "tools/list"
        {"result" => {"tools" => TOOLS}}
      when "tools/call"
        name = params["name"]
        timezone = params.dig("arguments", "timezone") || "UTC"
        text = "Current time in #{timezone} via #{name}: 12:00"
        {"result" => {"content" => [{"type" => "text", "text" => text}]}}
      else
        {"error" => {"code" => -32601, "message" => "Method not found: #{method}"}}
      end
    end
  end

  def mcp_client(server)
    http_instance = Object.new
    http_instance.define_singleton_method(:use_ssl=) { |_| }
    http_instance.define_singleton_method(:post) do |_path, body, _headers|
      parsed = JSON.parse(body)
      payload = server.call(parsed["method"], parsed["params"] || {})
      res_body = JSON.generate({"jsonrpc" => "2.0", "id" => parsed["id"]}.merge(payload))
      res = Net::HTTPSuccess.new("1.1", "200", "OK")
      res.instance_variable_set(:@body, res_body)
      def res.body = @body
      res
    end
    factory = Object.new
    factory.define_singleton_method(:new) { |_, _| http_instance }
    Rixie::MCP::Http::Client.new(url: "http://localhost:9000/mcp", http_client: factory)
  end

  def test_tools_are_fetched_from_mcp_server
    tools = mcp_client(StubMCPServer.new).tools
    assert_equal 1, tools.size
    tool = tools.first
    assert_kind_of Rixie::Tool, tool
    assert_equal "get_time", tool.name
    assert_equal "Returns the current time for a given timezone.", tool.description
    assert_equal StubMCPServer::TOOLS.first["inputSchema"], tool.input_schema
  end

  def test_session_uses_mcp_tools_in_agent_loop
    tools = mcp_client(StubMCPServer.new).tools
    llm_client = build_client(responses: [
      tool_call_response(id: "c1", name: "get_time", arguments: {"timezone" => "Asia/Tokyo"}),
      finish_response(content: "The current time in Asia/Tokyo is 12:00.")
    ])
    session = Rixie::Session.new(
      instructions: "You are a time assistant. Use get_time to answer questions.",
      tools: tools,
      llm_client: llm_client
    )

    output = session.chat("What time is it in Tokyo?")

    task = session.tasks.first
    assert task.completed?
    assert_instance_of String, output
    refute_empty output

    unless live?
      assert_equal "The current time in Asia/Tokyo is 12:00.", output
      thought = task.runs.first.thoughts.find(&:tool_call?)
      assert_equal "get_time", thought.tool_calls.first.name
      assert_equal "Current time in Asia/Tokyo via get_time: 12:00", thought.tool_results.first[:content]
    end
  end

  def test_mcp_tool_result_flows_back_to_llm
    tools = mcp_client(StubMCPServer.new).tools
    llm_client = build_client(responses: [
      tool_call_response(id: "c1", name: "get_time", arguments: {"timezone" => "UTC"}),
      tool_call_response(id: "c2", name: "get_time", arguments: {"timezone" => "America/New_York"}),
      finish_response(content: "UTC is 12:00, New York is 12:00.")
    ])
    session = Rixie::Session.new(
      instructions: "Use get_time for each timezone.",
      tools: tools,
      llm_client: llm_client
    )

    output = session.chat("What time is it in UTC and New York?")

    unless live?
      tool_thoughts = session.tasks.first.runs.first.thoughts.select(&:tool_call?)
      assert_equal 2, tool_thoughts.size
    end

    assert session.tasks.first.completed?
    assert_instance_of String, output
  end
end
