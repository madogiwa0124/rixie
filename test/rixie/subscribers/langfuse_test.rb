# frozen_string_literal: true

require "test_helper"
require "rixie/subscribers/langfuse"

class SubscribersLangfuseTest < Minitest::Test
  def setup
    super
    @flushed = nil
    @sub = Rixie::Subscribers::Langfuse.new(
      base_url: "http://localhost:3000",
      public_key: "pk-test",
      secret_key: "sk-test",
      flusher: ->(batch) { @flushed = batch }
    )
    @listener = Rixie::EventListener.new(session_id: "sess-1", task_id: "task-1")
    @listener.run_id = "run-1"
    @sub.subscribe(@listener)
  end

  def strategy
    Rixie::Strategy::Simple.new
  end

  def tool_call(id: "tc-1", name: "get_weather", arguments: {"city" => "Tokyo"})
    Rixie::LLM::ToolCall.new(id: id, name: name, arguments: arguments)
  end

  def result(content: "Sunny", error: nil)
    Rixie::ToolExecutor::Result.new(tool_call_id: "tc-1", content: content, error: error)
  end

  def flush!
    @listener.emit(Rixie::Event::TaskEnd.new(output: "done", status: "completed"))
  end

  # --- TaskStart ---

  def test_task_start_adds_trace_create
    @listener.emit(Rixie::Event::TaskStart.new(user_input: "Hello", strategy: strategy))
    flush!

    item = @flushed.find { |e| e[:type] == "trace-create" }
    assert item
    assert_equal "Hello", item.dig(:body, :input)
    assert_equal "Hello", item.dig(:body, :name)
    assert_includes item.dig(:body, :tags), "rixie"
    assert_equal "sess-1", item.dig(:body, :sessionId)
  end

  def test_task_start_truncates_long_name
    long_input = "A" * 200
    @listener.emit(Rixie::Event::TaskStart.new(user_input: long_input, strategy: strategy))
    flush!

    name = @flushed.find { |e| e[:type] == "trace-create" }.dig(:body, :name)
    assert name.length <= 100
    assert name.end_with?("...")
  end

  # --- RunStart ---

  def test_run_start_adds_span_create_for_run
    @listener.emit(Rixie::Event::RunStart.new(user_input: "Hello"))
    flush!

    item = @flushed.find { |e| e[:type] == "span-create" && e.dig(:body, :name) == "run" }
    assert item
    assert_equal "Hello", item.dig(:body, :input)
    refute_nil item.dig(:body, :traceId)
  end

  # --- LlmCallStart / LlmCallEnd ---

  def test_llm_call_start_adds_generation_create
    @listener.emit(Rixie::Event::RunStart.new(user_input: "Hi"))
    @listener.emit(Rixie::Event::LlmCallStart.new(model: "gpt-4o", provider: "openai"))
    flush!

    item = @flushed.find { |e| e[:type] == "generation-create" }
    assert item
    assert_equal "llm_call", item.dig(:body, :name)
    assert_equal "gpt-4o", item.dig(:body, :model)
    assert_equal "openai", item.dig(:body, :metadata, :provider)
  end

  def test_llm_call_start_links_to_run_span
    @listener.emit(Rixie::Event::RunStart.new(user_input: "Hi"))
    @listener.emit(Rixie::Event::LlmCallStart.new(model: "gpt-4o", provider: "openai"))
    flush!

    run_span_id = @flushed.find { |e| e[:type] == "span-create" && e.dig(:body, :name) == "run" }&.dig(:body, :id)
    gen_parent_id = @flushed.find { |e| e[:type] == "generation-create" }&.dig(:body, :parentObservationId)
    assert_equal run_span_id, gen_parent_id
  end

  def test_llm_call_end_adds_generation_update_with_usage
    @listener.emit(Rixie::Event::RunStart.new(user_input: "Hi"))
    @listener.emit(Rixie::Event::LlmCallStart.new(model: "gpt-4o", provider: "openai"))
    @listener.emit(Rixie::Event::LlmCallEnd.new(usage: {input_tokens: 100, output_tokens: 50}, finish_reason: "stop"))
    flush!

    item = @flushed.find { |e| e[:type] == "generation-update" }
    assert item
    assert_equal 100, item.dig(:body, :usage, :input)
    assert_equal 50, item.dig(:body, :usage, :output)
    assert_equal "TOKENS", item.dig(:body, :usage, :unit)
    assert_equal "stop", item.dig(:body, :metadata, :finish_reason)
  end

  def test_llm_call_end_without_matching_start_is_ignored
    @listener.emit(Rixie::Event::LlmCallEnd.new(usage: {input_tokens: 0, output_tokens: 0}, finish_reason: "stop"))
    flush!

    assert_empty @flushed.select { |e| e[:type] == "generation-update" }
  end

  # --- ToolCallStart / ToolCallEnd ---

  def test_tool_call_start_adds_span_create
    @listener.emit(Rixie::Event::RunStart.new(user_input: "Hi"))
    @listener.emit(Rixie::Event::ToolCallStart.new(tool_call: tool_call))
    flush!

    item = @flushed.find { |e| e[:type] == "span-create" && e.dig(:body, :name) == "get_weather" }
    assert item
    assert_equal({"city" => "Tokyo"}, item.dig(:body, :input))
  end

  def test_tool_call_end_adds_span_update_with_output
    @listener.emit(Rixie::Event::RunStart.new(user_input: "Hi"))
    @listener.emit(Rixie::Event::ToolCallStart.new(tool_call: tool_call))
    @listener.emit(Rixie::Event::ToolCallEnd.new(tool_call: tool_call, result: result(content: "Sunny")))
    flush!

    # span-update for the tool (not the run, which also produces span-update on RunEnd)
    # identify by checking output = "Sunny"
    item = @flushed.find { |e| e[:type] == "span-update" && e.dig(:body, :output) == "Sunny" }
    assert item
    assert_equal "DEFAULT", item.dig(:body, :level)
  end

  def test_tool_call_end_marks_error_level_when_tool_raised
    @listener.emit(Rixie::Event::RunStart.new(user_input: "Hi"))
    @listener.emit(Rixie::Event::ToolCallStart.new(tool_call: tool_call))
    @listener.emit(Rixie::Event::ToolCallEnd.new(
      tool_call: tool_call,
      result: result(content: "Error: boom", error: RuntimeError.new("boom"))
    ))
    flush!

    item = @flushed.find { |e| e[:type] == "span-update" && e.dig(:body, :output) == "Error: boom" }
    assert item
    assert_equal "ERROR", item.dig(:body, :level)
  end

  def test_tool_call_end_without_matching_start_is_ignored
    @listener.emit(Rixie::Event::ToolCallEnd.new(tool_call: tool_call(id: "unknown"), result: result))
    flush!

    assert_empty @flushed.select { |e| e[:type] == "span-update" }
  end

  # --- RunEnd ---

  def test_run_end_updates_run_span
    @listener.emit(Rixie::Event::RunStart.new(user_input: "Hi"))
    @listener.emit(Rixie::Event::RunEnd.new(output: "Done", status: "completed"))
    flush!

    item = @flushed.find { |e| e[:type] == "span-update" && e.dig(:body, :output) == "Done" }
    assert item
    assert_equal "DEFAULT", item.dig(:body, :level)
  end

  def test_run_end_marks_error_when_failed
    @listener.emit(Rixie::Event::RunStart.new(user_input: "Hi"))
    @listener.emit(Rixie::Event::RunEnd.new(output: nil, status: "failed"))
    flush!

    item = @flushed.find { |e| e[:type] == "span-update" }
    assert item
    assert_equal "ERROR", item.dig(:body, :level)
  end

  # --- TaskEnd / flush ---

  def test_task_end_appends_trace_update_and_flushes
    emit_full_task

    assert_instance_of Array, @flushed
    trace_updates = @flushed.select { |e| e[:type] == "trace-create" }
    assert trace_updates.size >= 2, "expected at least 2 trace-create events (initial + output update)"
    output_update = trace_updates.find { |e| e.dig(:body, :output) == "result" }
    assert output_update
  end

  def test_flushed_batch_contains_all_event_types
    emit_full_task

    types = @flushed.map { |e| e[:type] }
    assert_includes types, "trace-create"
    assert_includes types, "span-create"       # run span
    assert_includes types, "generation-create"
    assert_includes types, "generation-update"
    assert_includes types, "span-update"       # tool end + run end
    assert_equal 2, types.count("trace-create")
  end

  def test_each_ingestion_event_has_id_type_timestamp_body
    emit_full_task

    @flushed.each do |item|
      assert item[:id], "missing :id on #{item[:type]}"
      assert item[:type], "missing :type"
      assert item[:timestamp], "missing :timestamp on #{item[:type]}"
      assert item[:body], "missing :body on #{item[:type]}"
    end
  end

  def test_ingestion_partial_failure_is_logged
    log_output = StringIO.new
    Rixie.config.logger = ::Logger.new(log_output)

    error_body = JSON.generate({
      "successes" => [],
      "errors" => [{"id" => "evt-1", "status" => 400, "error" => "Invalid event type"}]
    })
    fake_response = Net::HTTPSuccess.new("1.1", "207", "Multi-Status")
    fake_response.instance_variable_set(:@body, error_body)
    fake_response.instance_variable_set(:@read, true)

    sub = Rixie::Subscribers::Langfuse.new(
      base_url: "http://localhost:3000",
      public_key: "pk",
      secret_key: "sk"
    )
    listener = Rixie::EventListener.new
    sub.subscribe(listener)

    Net::HTTP.stub(:new, ->(*) {
      http = Object.new
      http.define_singleton_method(:use_ssl=) { |_| }
      http.define_singleton_method(:open_timeout=) { |_| }
      http.define_singleton_method(:read_timeout=) { |_| }
      http.define_singleton_method(:request) { |_| fake_response }
      http
    }) do
      listener.emit(Rixie::Event::TaskEnd.new(output: "done", status: "completed"))
    end

    assert_match "[Langfuse] ingestion partial failure", log_output.string
    assert_match "Invalid event type", log_output.string
  end

  def test_flush_error_is_rescued_and_logged
    log_output = StringIO.new
    Rixie.config.logger = ::Logger.new(log_output)

    sub = Rixie::Subscribers::Langfuse.new(
      base_url: "http://localhost:3000",
      public_key: "pk",
      secret_key: "sk",
      flusher: ->(_) { raise "connection refused" }
    )
    listener = Rixie::EventListener.new
    sub.subscribe(listener)

    assert_silent { listener.emit(Rixie::Event::TaskEnd.new(output: "done", status: "completed")) }
    assert_match "[Langfuse]", log_output.string
    assert_match "connection refused", log_output.string
  end

  private

  def emit_full_task
    tc = tool_call
    @listener.emit(Rixie::Event::TaskStart.new(user_input: "Hello", strategy: strategy))
    @listener.emit(Rixie::Event::RunStart.new(user_input: "Hello"))
    @listener.emit(Rixie::Event::LlmCallStart.new(model: "gpt-4o", provider: "openai"))
    @listener.emit(Rixie::Event::ToolCallStart.new(tool_call: tc))
    @listener.emit(Rixie::Event::ToolCallEnd.new(tool_call: tc, result: result))
    @listener.emit(Rixie::Event::LlmCallEnd.new(usage: {input_tokens: 10, output_tokens: 5}, finish_reason: "stop"))
    @listener.emit(Rixie::Event::RunEnd.new(output: "result", status: "completed"))
    @listener.emit(Rixie::Event::TaskEnd.new(output: "result", status: "completed"))
  end
end
