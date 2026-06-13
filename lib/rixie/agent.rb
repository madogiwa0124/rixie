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

    def think(messages:, listener:, schema: nil)
      thoughts = []
      tool_call_count = 0
      step_count = 0
      # Work on a private copy so the caller's `messages` array is never mutated
      # as `think` grows the conversation across the loop.
      conversation = messages.dup

      loop do
        step_count += 1
        thought = llm_call(
          conversation:, step: step_count,
          on_start: ->(step) { listener.emit(Event::LlmCallStart.new(step_count: step, model: @llm_client.model, provider: @llm_client.provider)) },
          on_end: ->(step, usage, finish_reason) { listener.emit(Event::LlmCallEnd.new(step_count: step, usage: usage, finish_reason: finish_reason)) },
          on_event: ->(event) { listener.emit(event) }
        )

        case thought.type
        when :tool_call
          raise MaxStepsExceededError, "Max steps (#{@max_steps}) exceeded" if tool_call_count >= @max_steps
          tool_call_count += 1
          tool_results = call_thought_tools(
            thought:,
            on_start: ->(tool_call) { listener.emit(Event::ToolCallStart.new(tool_call:)) },
            on_end: ->(tool_call, result) { listener.emit(Event::ToolCallEnd.new(tool_call:, result:)) },
            parallel: @parallel_tool_calls
          )
          listener.emit(Event::ToolCallsCompleted.new(tool_calls: thought.tool_calls, tool_results:))
          thought = record_thought(thoughts, thought, tool_results)
          append_thought_messages(conversation, thought)
          if @tool_executor.return_direct?(thought.tool_calls)
            listener.emit(Event::Finished.new(content: nil))
            return ThinkResult.new(content: nil, thoughts:)
          end
        when :finish
          thoughts << thought
          content = thought.content
          if schema
            # Schema is applied only here: the main loop runs unconstrained. On
            # validation failure ONLY the finish answer is re-generated (schema
            # applied, tools dropped) — tool calls are never re-run.
            result = generate_structured_output(
              conversation:, content:, schema:, start_step: step_count,
              max_retries: StructuredOutput::DEFAULT_MAX_RETRIES,
              on_start: ->(step) { listener.emit(Event::LlmCallStart.new(step_count: step, model: @llm_client.model, provider: @llm_client.provider)) },
              on_end: ->(step, usage, finish_reason) { listener.emit(Event::LlmCallEnd.new(step_count: step, usage: usage, finish_reason: finish_reason)) },
              on_event: ->(event) { listener.emit(event) }
            )
            content = result.value
          end
          listener.emit(Event::ThoughtCompleted.new(thought:))
          listener.emit(Event::Finished.new(content:))
          return ThinkResult.new(content:, thoughts:)
        else
          raise Rixie::AgentError, "Unknown thought type: #{thought.type.inspect}"
        end
      end
    end

    private

    def calculate_token_usage(conversation, response)
      input_tokens = @token_counter.call(conversation)
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

    # Appends a completed tool-call thought to the conversation buffer: the
    # assistant turn plus one tool-result message per tool call. Mutates the
    # `conversation` buffer, which `think` owns (a dup of the caller's array).
    def append_thought_messages(conversation, thought)
      conversation << Message::Assistant.new(content: thought.content, tool_calls: thought.tool_calls)
      thought.tool_results.each { |r| conversation << Message::Tool.new(tool_call_id: r.tool_call_id, content: r.content) }
    end

    # Owns the structured-output retry loop. Parses `content` against the schema
    # via the pure `StructuredOutput`, and on failure appends a corrective message
    # and re-generates ONLY the finish answer (`llm_call` with schema, tools
    # dropped) until it conforms or `max_retries` is exhausted. Emission is
    # injected (`on_start` / `on_end` / `on_event`) so it stays in the public
    # `think` (see .claude/rules/events.md). Returns a `StructuredOutput::Result`.
    # `start_step` is the step number of the original finish call; each retry is a
    # further LLM call, numbered `start_step + attempts` for event continuity.
    def generate_structured_output(conversation:, content:, schema:, start_step:, max_retries:, on_start:, on_end:, on_event:)
      structured = StructuredOutput.new(schema:)
      result = structured.parse(content)
      attempts = 0

      until result.valid?
        raise SchemaValidationError, "Failed to produce schema-conforming output after #{max_retries} retries: #{result.error}" if attempts >= max_retries
        attempts += 1
        conversation << structured.correction_message(content, result.error)
        content = llm_call(conversation:, step: start_step + attempts, schema:, on_start:, on_end:, on_event:).content
        result = structured.parse(content)
      end

      result
    end

    # One LLM turn with its LlmCall* lifecycle: fires `on_start` before the call
    # and `on_end` after (with the resolved usage), and returns the decoded
    # Thought. Holds no `listener` reference — emission is the caller's concern,
    # passed via the `on_start` / `on_end` / `on_event` (per-token) lambdas.
    def llm_call(conversation:, step:, on_start:, on_end:, on_event:, schema: nil)
      on_start.call(step)
      # The schema-constrained finish request drops tools: some providers cannot
      # combine tool calling and structured output in the same request, and the
      # finish turn never calls a tool.
      tools = schema ? [] : @tool_executor.definitions
      response = @llm_client.call(conversation, tools:, schema:) { on_event.call(it) }
      raise LLM::ResponseTruncatedError, "LLM response truncated (finish_reason=length)" if response.finish_reason == "length"
      usage = response.usage || calculate_token_usage(conversation, response)
      on_end.call(step, usage, response.finish_reason)
      if response.has_tool_calls?
        Thought.new(type: :tool_call, content: response.content, tool_calls: response.tool_calls, tool_results: nil)
      else
        Thought.new(type: :finish, content: response.content, tool_calls: [], tool_results: nil)
      end
    end
  end
end
