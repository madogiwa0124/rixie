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
      # Work on a private copy so the caller's `messages` array is never mutated
      # as the loop grows the conversation.
      conversation = messages.dup

      loop do
        response = generate(messages: conversation, listener:)

        if response.has_tool_calls?
          raise MaxStepsExceededError, "Max steps (#{@max_steps}) exceeded" if tool_call_count >= @max_steps
          tool_call_count += 1
          response.tool_calls.each { |tc| listener.emit(Event::ToolCallStart.new(tool_call: tc)) }
          tool_results = execute_tools(response.tool_calls)
          response.tool_calls.zip(tool_results).each { |tc, result| listener.emit(Event::ToolCallEnd.new(tool_call: tc, result:)) }
          listener.emit(Event::ToolCallsCompleted.new(tool_calls: response.tool_calls, tool_results:))
          thought = Thought.new(type: :tool_call, content: response.content, tool_calls: response.tool_calls, tool_results:)
          thoughts << thought
          append_thought_messages(conversation, thought)
          if @tool_executor.return_direct?(thought.tool_calls)
            listener.emit(Event::Finished.new(content: nil))
            return ThinkResult.new(content: nil, thoughts:)
          end
        else
          thought = Thought.new(type: :finish, content: response.content, tool_calls: [], tool_results: nil)
          thoughts << thought
          # Schema is applied only here: the loop runs unconstrained. On validation
          # failure ONLY the finish answer is re-generated (schema applied, tools
          # dropped) — tool calls are never re-run.
          content = schema ? generate_structured_output(conversation:, content: thought.content, schema:, listener:) : thought.content
          listener.emit(Event::ThoughtCompleted.new(thought:))
          listener.emit(Event::Finished.new(content:))
          return ThinkResult.new(content:, thoughts:)
        end
      end
    end

    # Runs one LLM turn for the given messages: it calls the model (tools dropped
    # when a schema is given — the schema-constrained finish request must not call
    # tools), emits the `LlmCall*` lifecycle (plus streamed token events), and
    # returns the raw `LLM::Response`. `think` interprets it (tool_call vs finish)
    # and builds the loop's `Thought` records. Self-contained: start/end events need
    # no externally-supplied step number (subscribers correlate by `run_id`, and the
    # envelope already carries a `sequence_number`).
    def generate(messages:, listener:, schema: nil)
      listener.emit(Event::LlmCallStart.new(model: @llm_client.model, provider: @llm_client.provider))
      tools = schema ? [] : @tool_executor.definitions
      response = @llm_client.call(messages, tools:, schema:) { |event| listener.emit(event) }
      raise LLM::ResponseTruncatedError, "LLM response truncated (finish_reason=length)" if response.finish_reason == "length"
      usage = response.usage || calculate_token_usage(messages, response)
      listener.emit(Event::LlmCallEnd.new(usage:, finish_reason: response.finish_reason))
      response
    end

    private

    # Parses the finish answer against the schema via the pure StructuredOutput,
    # and on failure appends a corrective message and re-generates only the finish
    # answer (each retry is another `generate` call). Returns the parsed value, or
    # raises after the retry budget is exhausted.
    def generate_structured_output(conversation:, content:, schema:, listener:)
      structured = StructuredOutput.new(schema:)
      result = structured.parse(content)
      attempts = 0

      until result.valid?
        if attempts >= StructuredOutput::DEFAULT_MAX_RETRIES
          raise SchemaValidationError, "Failed to produce schema-conforming output after #{StructuredOutput::DEFAULT_MAX_RETRIES} retries: #{result.error}"
        else
          attempts += 1
          conversation << structured.correction_message(content, result.error)
          content = generate(messages: conversation, listener:, schema:).content
          result = structured.parse(content)
        end
      end

      result.value
    end

    def execute_tools(tool_calls)
      return tool_calls.map { @tool_executor.execute(it) } unless @parallel_tool_calls

      concurrent_map(tool_calls) { @tool_executor.execute(it) }
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
      first_error = outcomes.find { it.key?(:err) }&.fetch(:err)
      raise first_error if first_error
      outcomes.map { it[:ok] }
    end

    def append_thought_messages(conversation, thought)
      conversation << Message::Assistant.new(content: thought.content, tool_calls: thought.tool_calls)
      thought.tool_results.each do
        conversation << Message::Tool.new(tool_call_id: it.tool_call_id, content: it.content)
      end
    end

    def calculate_token_usage(conversation, response)
      {
        input_tokens: @token_counter.call(conversation),
        output_tokens: @token_counter.call([response])
      }
    end
  end
end
