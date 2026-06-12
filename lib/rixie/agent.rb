# frozen_string_literal: true

module Rixie
  class Agent
    Thought = Data.define(:type, :content, :tool_calls, :tool_results) do
      def tool_call? = type == :tool_call
      def finish? = type == :finish
    end

    ThinkResult = Data.define(:content, :thoughts)

    DEFAULT_MAX_STEPS = 10

    attr_reader :instructions, :tools, :llm_client, :max_steps, :parallel_tool_calls, :token_counter

    def initialize(instructions:, llm_client:, tools: [], max_steps: nil, parallel_tool_calls: false, token_counter: nil)
      @instructions = instructions
      @tools = tools
      @max_steps = max_steps || DEFAULT_MAX_STEPS
      @parallel_tool_calls = parallel_tool_calls
      @token_counter = token_counter || TokenCounter::DEFAULT
      @tool_executor = ToolExecutor.new(tools: tools)
      @llm_client = llm_client
    end

    def with_llm_client(llm_client)
      Agent.new(
        instructions: @instructions,
        tools: @tools,
        max_steps: @max_steps,
        llm_client: llm_client,
        parallel_tool_calls: @parallel_tool_calls,
        token_counter: @token_counter
      )
    end

    def think(messages:, listener:)
      thoughts = []
      tool_call_count = 0
      step_count = 0

      loop do
        step_count += 1
        listener.emit(Event::LlmCallStart.new(step_count: step_count, model: @llm_client.model, provider: @llm_client.provider))
        thought, response = llm_call(messages:) { |event| listener.emit(event) }
        usage = response.usage || calculate_token_usage(messages, response)
        listener.emit(Event::LlmCallEnd.new(step_count: step_count, usage: usage, finish_reason: response.finish_reason))

        if thought.tool_call?
          raise MaxStepsExceededError, "Max steps (#{@max_steps}) exceeded" if tool_call_count >= @max_steps
          tool_call_count += 1
          results = call_thought_tools(
            on_start: ->(tc) { listener.emit(Event::ToolCallStart.new(tool_call: tc)) },
            thought: thought,
            on_end: ->(tc, result) { listener.emit(Event::ToolCallEnd.new(tool_call: tc, result: result)) },
            parallel: @parallel_tool_calls
          )

          listener.emit(Event::ToolCallsCompleted.new(tool_calls: thought.tool_calls, tool_results: results))

          thought = record_thought(thoughts, thought, results)
          append_thought_messages(messages, thought)

          if @tool_executor.return_direct?(thought.tool_calls)
            listener.emit(Event::Finished.new(content: nil))
            return ThinkResult.new(content: nil, thoughts: thoughts)
          end
        elsif thought.finish?
          thoughts << thought
          listener.emit(Event::ThoughtCompleted.new(thought: thought))
          listener.emit(Event::Finished.new(content: thought.content))
          return ThinkResult.new(content: thought.content, thoughts: thoughts)
        else
          raise Rixie::AgentError, "Unknown thought type: #{thought.type.inspect}"
        end
      end
    end

    private

    def calculate_token_usage(messages, response)
      input_tokens = @token_counter.call(messages)
      output_tokens = @token_counter.call([response])
      {input_tokens: input_tokens, output_tokens: output_tokens}
    end

    def call_thought_tools(on_start:, thought:, on_end:, parallel:)
      thought.tool_calls.each { |tc| on_start.call(tc) }
      results = parallel ? concurrent_map(thought.tool_calls) { |tc| @tool_executor.execute(tc) } : thought.tool_calls.map { |tc| @tool_executor.execute(tc) }
      thought.tool_calls.zip(results).each { |tc, result| on_end.call(tc, result) }
      results
    end

    def concurrent_map(items, &block)
      # Capture exceptions as values inside each thread so no thread dies with an unhandled exception.
      # This prevents stderr noise from Thread.report_on_exception and ensures all threads are joined
      # before raising. Ruby has no safe cancellation, so we always wait for every thread to finish.
      threads = items.map do |item|
        Thread.new do
          {ok: block.call(item)}
        rescue => e
          {err: e}
        end
      end
      outcomes = threads.map(&:value)
      first_error = outcomes.find { |o| o.key?(:err) }&.fetch(:err)
      raise first_error if first_error
      outcomes.map { |o| o[:ok] }
    end

    def record_thought(thoughts, thought, results)
      thought = thought.with(tool_results: results)
      thoughts << thought
      thought
    end

    def append_thought_messages(messages, thought)
      messages << Message::Assistant.new(content: thought.content, tool_calls: thought.tool_calls)
      thought.tool_results.each { |r| messages << Message::Tool.new(tool_call_id: r.tool_call_id, content: r.content) }
    end

    def llm_call(messages:, &on_event)
      response = @llm_client.call(messages, tools: @tool_executor.definitions) { |event| on_event.call(event) }
      raise LLM::ResponseTruncatedError, "LLM response truncated (finish_reason=length)" if response.finish_reason == "length"
      thought = if response.has_tool_calls?
        Thought.new(type: :tool_call, content: response.content, tool_calls: response.tool_calls, tool_results: nil)
      else
        Thought.new(type: :finish, content: response.content, tool_calls: [], tool_results: nil)
      end
      [thought, response]
    end
  end
end
