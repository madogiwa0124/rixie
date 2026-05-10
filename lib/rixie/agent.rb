# frozen_string_literal: true

module Rixie
  class Agent
    Thought = Data.define(:type, :content, :tool_calls)

    DEFAULT_MAX_STEPS = 10

    attr_reader :instructions, :tools, :llm_client

    def initialize(instructions:, llm_client:, tools: [], max_steps: nil)
      @instructions = instructions
      @tools = tools
      @max_steps = max_steps || DEFAULT_MAX_STEPS
      @tool_executor = ToolExecutor.new(tools: tools)
      @llm_client = llm_client
    end

    def think(messages:, listener:)
      step_count = 0

      loop do
        thought = llm_call(messages:)

        case thought.type
        when :tool_call
          tool_results = @tool_executor.execute(thought.tool_calls)
          listener.emit(:step_completed, {tool_calls: thought.tool_calls, tool_results: tool_results})
          messages << {role: "assistant", content: nil, tool_calls: thought.tool_calls.map(&:to_llm_format)}
          tool_results.each { |r| messages << {role: "tool", tool_call_id: r[:tool_call_id], content: r[:content]} }
          step_count += 1
          raise MaxStepsExceededError, "Max steps (#{@max_steps}) exceeded" if step_count >= @max_steps
        when :finish
          listener.emit(:finished, {content: thought.content})
          return thought.content
        end
      end
    end

    private

    def llm_call(messages:)
      response = @llm_client.chat(messages, tools: @tool_executor.definitions)
      if response.has_tool_calls?
        Thought.new(
          type: :tool_call,
          content: nil,
          tool_calls: response.tool_calls.map { ToolCall.build_from_raw(it) }
        )
      else
        Thought.new(type: :finish, content: response.content, tool_calls: [])
      end
    end
  end
end
