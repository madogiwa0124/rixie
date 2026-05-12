# frozen_string_literal: true

module Rixie
  class ToolExecutor
    def initialize(tools: [])
      @tools = tools.each_with_object({}) { |t, h| h[t.name] = t }
    end

    def execute(tool_calls)
      tool_calls.map do |tool_call|
        tool = @tools[tool_call.name]
        raise Rixie::ToolNotFoundError, "Tool not found: #{tool_call.name.inspect}" if tool.nil?

        result = tool.call(tool_call.arguments)
        {tool_call_id: tool_call.id, content: result.to_s}
      end
    end

    def return_direct?(tool_calls)
      tool_calls.any? { |tc| @tools[tc.name]&.return_direct? }
    end

    def definitions
      @tools.values
    end
  end
end
