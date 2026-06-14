# frozen_string_literal: true

require "test_helper"
require "rixie/subscribers/open_telemetry"

# Minimal stub for OpenTelemetry modules used by the subscriber at event-fire time.
module OpenTelemetry
  module Trace
    def self.context_with_span(span)
      {span: span}
    end

    class Status
      attr_reader :code, :description

      def self.error(description = "")
        new(2, description)
      end

      def self.ok
        new(1, "")
      end

      def initialize(code, description)
        @code = code
        @description = description
      end
    end
  end
end

class SubscribersOpenTelemetryTest < Minitest::Test
  class FakeSpan
    attr_reader :name, :attributes, :status
    attr_writer :status

    def initialize(name, attributes: {})
      @name = name
      @attributes = (attributes || {}).dup
      @finished = false
    end

    def set_attribute(key, value)
      @attributes[key] = value
    end

    def finish
      @finished = true
    end

    def finished? = @finished
  end

  class FakeTracer
    attr_reader :spans

    def initialize
      @spans = []
    end

    def start_span(name, attributes: nil, with_parent: nil, kind: nil, **)
      span = FakeSpan.new(name, attributes: attributes)
      @spans << span
      span
    end
  end

  class FakeTracerProvider
    def initialize(tracer)
      @tracer = tracer
    end

    def tracer(name, version = nil) = @tracer
  end

  def setup
    super
    @tracer = FakeTracer.new
    provider = FakeTracerProvider.new(@tracer)
    @sub = Rixie::Subscribers::OpenTelemetry.new(
      service_name: "test-app",
      tracer_provider: provider
    )
    @listener = Rixie::EventListener.new(session_id: "sess-1", task_id: "task-1")
    @listener.run_id = "run-1"
    @sub.subscribe(@listener)
  end

  def strategy = Rixie::Strategy::Simple.new
  def spans = @tracer.spans

  def tool_call(id: "tc-1", name: "get_weather", arguments: {"city" => "Tokyo"})
    Rixie::LLM::ToolCall.new(id: id, name: name, arguments: arguments)
  end

  def result(content: "Sunny", error: nil)
    Rixie::ToolExecutor::Result.new(tool_call_id: "tc-1", content: content, error: error)
  end

  def emit_full_task(tool_calls: false)
    @listener.emit(Rixie::Event::TaskStart.new(user_input: "Hello", strategy: strategy))
    @listener.emit(Rixie::Event::RunStart.new(user_input: "Hello"))
    @listener.emit(Rixie::Event::LlmCallStart.new(model: "gpt-4o", provider: "openai"))
    if tool_calls
      tc = tool_call
      @listener.emit(Rixie::Event::ToolCallStart.new(tool_call: tc))
      @listener.emit(Rixie::Event::ToolCallEnd.new(tool_call: tc, result: result))
    end
    @listener.emit(Rixie::Event::LlmCallEnd.new(usage: {input_tokens: 10, output_tokens: 5}, finish_reason: "stop"))
    @listener.emit(Rixie::Event::RunEnd.new(output: "Done", status: "completed"))
    @listener.emit(Rixie::Event::TaskEnd.new(output: "Done", status: "completed"))
  end

  # --- TaskStart / TaskEnd ---

  def test_task_span_created_and_finished
    emit_full_task
    task_span = spans.find { |s| s.name == "task" }
    assert task_span, "expected a 'task' span"
    assert task_span.finished?
    assert_equal "Rixie::Strategy::Simple", task_span.attributes["rixie.task.strategy"]
    assert_equal "Hello", task_span.attributes["rixie.task.input"]
  end

  def test_task_span_status_error_on_failure
    @listener.emit(Rixie::Event::TaskStart.new(user_input: "Hi", strategy: strategy))
    @listener.emit(Rixie::Event::TaskEnd.new(output: nil, status: "failed"))
    task_span = spans.find { |s| s.name == "task" }
    assert_equal 2, task_span.status.code
    assert_equal "failed", task_span.status.description
  end

  # --- RunStart / RunEnd ---

  def test_run_span_created_and_finished
    emit_full_task
    run_span = spans.find { |s| s.name == "run" }
    assert run_span, "expected a 'run' span"
    assert run_span.finished?
    assert_equal "Hello", run_span.attributes["rixie.run.input"]
  end

  # --- LlmCallStart / LlmCallEnd ---

  def test_llm_span_created_with_attributes
    emit_full_task
    llm_span = spans.find { |s| s.name == "gen_ai.chat" }
    assert llm_span, "expected a 'gen_ai.chat' span"
    assert llm_span.finished?
    assert_equal "openai", llm_span.attributes["gen_ai.system"]
    assert_equal "gpt-4o", llm_span.attributes["gen_ai.request.model"]
  end

  def test_llm_span_receives_usage_on_end
    emit_full_task
    llm_span = spans.find { |s| s.name == "gen_ai.chat" }
    assert_equal 10, llm_span.attributes["gen_ai.usage.input_tokens"]
    assert_equal 5, llm_span.attributes["gen_ai.usage.output_tokens"]
    assert_equal "stop", llm_span.attributes["gen_ai.response.finish_reasons"]
  end

  # --- ToolCallStart / ToolCallEnd ---

  def test_tool_span_created_and_finished
    emit_full_task(tool_calls: true)
    tool_span = spans.find { |s| s.name == "tool.get_weather" }
    assert tool_span, "expected a 'tool.get_weather' span"
    assert tool_span.finished?
    assert_equal "get_weather", tool_span.attributes["gen_ai.tool.name"]
    assert_equal "tc-1", tool_span.attributes["rixie.tool.call_id"]
  end

  def test_tool_span_status_error_on_tool_failure
    @listener.emit(Rixie::Event::TaskStart.new(user_input: "Hi", strategy: strategy))
    @listener.emit(Rixie::Event::RunStart.new(user_input: "Hi"))
    tc = tool_call
    @listener.emit(Rixie::Event::ToolCallStart.new(tool_call: tc))
    @listener.emit(Rixie::Event::ToolCallEnd.new(tool_call: tc, result: result(content: "Error: boom", error: RuntimeError.new("boom"))))
    tool_span = spans.find { |s| s.name == "tool.get_weather" }
    assert_equal 2, tool_span.status.code
  end

  # --- Span ordering / count ---

  def test_span_order_task_run_llm
    emit_full_task
    names = spans.map(&:name)
    assert_equal ["task", "run", "gen_ai.chat"], names
  end

  def test_all_spans_finished_after_full_task
    emit_full_task(tool_calls: true)
    spans.each { |s| assert s.finished?, "span '#{s.name}' was not finished" }
  end

  # --- Missing task span guard ---

  def test_run_span_skipped_if_no_task_span
    @listener.emit(Rixie::Event::RunStart.new(user_input: "Hi"))
    assert_empty spans
  end
end
