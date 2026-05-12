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

    def with_llm_client(llm_client)
      Agent.new(
        instructions: @instructions,
        tools: @tools,
        max_steps: @max_steps,
        llm_client: llm_client
      )
    end

    def think(messages:, listener:)
      step_count = 0

      loop do
        Rixie.logger.info { "[Agent] llm_call ##{step_count + 1}" }
        thought = llm_call(messages:, listener:)

        case thought.type
        when :tool_call
          thought.tool_calls.each do |tc|
            Rixie.logger.info { "[Agent] tool_call: #{tc.name}(#{tc.arguments})" }
          end
          tool_results = @tool_executor.execute(thought.tool_calls)
          tool_results.each do |r|
            Rixie.logger.info { "[Agent] tool_result: #{r[:content].inspect}" }
          end
          listener.emit(Event::StepCompleted.new(tool_calls: thought.tool_calls, tool_results: tool_results))
          messages << {role: "assistant", content: nil, tool_calls: thought.tool_calls.map(&:to_llm_format)}
          tool_results.each { |r| messages << {role: "tool", tool_call_id: r[:tool_call_id], content: r[:content]} }
          step_count += 1
          raise MaxStepsExceededError, "Max steps (#{@max_steps}) exceeded" if step_count >= @max_steps
          return nil if @tool_executor.return_direct?(thought.tool_calls)
        when :finish
          Rixie.logger.info { "[Agent] finish: #{thought.content.inspect}" }
          listener.emit(Event::Finished.new(content: thought.content))
          return thought.content
        end
      end
    end

    private

    def llm_call(messages:, listener:)
      response = @llm_client.call(messages, tools: @tool_executor.definitions) { |event| listener.emit(event) }
      if response.finish_reason == "length"
        Rixie.logger.warn { "[Agent] LLM response truncated (finish_reason=length)" }
      end
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
