# MCP (Model Context Protocol)

Rixie supports fetching tools from any MCP server that exposes an HTTP endpoint.

```ruby
require "rixie/mcp"

mcp = Rixie::MCP::Http::Client.new(url: "http://localhost:8000/mcp")

session = Rixie::Session.new(
  instructions: "You are a helpful assistant.",
  tools: mcp.tools
)
puts session.chat("What tools do you have available?")
```

`mcp.tools` returns an array of `Rixie::Tool` objects ready to pass to `Session`. Tool discovery and invocation are handled automatically — the agent calls tools on the MCP server the same way it calls any other tool.

## Authentication and custom headers

Pass additional headers for authentication:

```ruby
mcp = Rixie::MCP::Http::Client.new(
  url:     "https://my-mcp-server.example.com/mcp",
  headers: {"Authorization" => "Bearer #{ENV["MCP_TOKEN"]}"}
)
```

## Combining MCP tools with local tools

MCP tools and local `Rixie::Tool` instances can be mixed freely:

```ruby
local_tool = Rixie::Tool.new(
  name:         "current_time",
  description:  "Returns the current time.",
  input_schema: {type: "object", properties: {}},
  call:         ->(_) { Time.now.to_s }
)

session = Rixie::Session.new(
  instructions: "You are a helpful assistant.",
  tools: mcp.tools + [local_tool]
)
```

## Error handling

| Error class | Raised when |
| --- | --- |
| `Rixie::MCP::TimeoutError` | Connection or read timeout |
| `Rixie::MCP::ProtocolError` | MCP server returns a JSON-RPC error |
| `Rixie::MCP::RequestError` | Network or other HTTP error |
