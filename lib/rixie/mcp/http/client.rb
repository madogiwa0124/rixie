# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Rixie
  module MCP
    module Http
      class Client
        MCP_PROTOCOL_VERSION = "2024-11-05"

        def initialize(url:, headers: {}, client_info: nil, http_client: nil)
          uri = URI.parse(url)
          @http = (http_client || Net::HTTP).new(uri.host, uri.port)
          @http.use_ssl = (uri.scheme == "https")
          @path = uri.path.empty? ? "/" : uri.path
          @headers = {"Content-Type" => "application/json", "Accept" => "application/json, text/event-stream"}.merge(headers)
          @client_info = client_info || {name: "rixie", version: Rixie::VERSION}
          @request_id = 0
          @session_initialized = false
        end

        def tools
          list_tools.map do |tool_def|
            name = tool_def["name"]
            Rixie::Tool.new(
              name: name,
              description: tool_def["description"],
              input_schema: tool_def["inputSchema"],
              call: ->(args) { call_tool(name, args) }
            )
          end
        end

        def list_tools
          initialize_session
          result = request("tools/list", {})
          result.dig("result", "tools") || []
        end

        def call_tool(name, arguments = {})
          initialize_session
          result = request("tools/call", {name: name, arguments: arguments})
          result.dig("result", "content").map { |c| c["text"] }.join
        end

        private

        def initialize_session
          return if @session_initialized

          request("initialize", {
            protocolVersion: MCP_PROTOCOL_VERSION,
            capabilities: {},
            clientInfo: @client_info
          })
          @session_initialized = true
        end

        def request(method, params)
          @request_id += 1
          body = JSON.generate({jsonrpc: "2.0", id: @request_id, method: method, params: params})

          response = @http.post(@path, body, @headers)
          parsed = JSON.parse(response.body)

          if parsed["error"]
            raise Rixie::MCP::ProtocolError, parsed.dig("error", "message")
          end

          parsed
        rescue Rixie::MCP::Error
          raise
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          raise Rixie::MCP::TimeoutError, e.message
        rescue => e
          raise Rixie::MCP::RequestError, e.message
        end
      end
    end
  end
end
