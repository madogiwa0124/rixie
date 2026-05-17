# frozen_string_literal: true

module Rixie
  class ToolExecutor
    Result = Data.define(:tool_call_id, :content, :error) do
      def success? = error.nil?
      def error? = !error.nil?
    end

    def initialize(tools: [])
      @tools = tools.each_with_object({}) { |t, h| h[t.name] = t }
    end

    def execute(tool_call)
      tool = @tools[tool_call.name]
      raise Rixie::ToolNotFoundError, "Tool not found: #{tool_call.name.inspect}" if tool.nil?

      content = tool.call(tool_call.arguments)
      Result.new(tool_call_id: tool_call.id, content: content.to_s, error: nil)
    rescue ToolNotFoundError
      raise # configuration bug, not a tool runtime error — let it propagate
    rescue => e
      Result.new(tool_call_id: tool_call.id, content: "Error: #{e.message}", error: e)
    end

    def return_direct?(tool_calls)
      tool_calls.any? { |tc| @tools[tc.name]&.return_direct? }
    end

    def definitions
      @tools.values
    end
  end
end
