# frozen_string_literal: true

require "test_helper"
require "json"

class SubscribersJsonLoggerTest < Minitest::Test
  def make_logger
    log_output = StringIO.new
    logger = ::Logger.new(log_output)
    logger.formatter = ->(_sev, _time, _prog, msg) { "#{msg}\n" }
    [logger, log_output]
  end

  def make_subscriber(logger)
    Rixie::Subscribers::JsonLogger.new(logger: logger)
  end

  def listener
    @listener ||= Rixie::EventListener.new
  end

  def last_record(log_output)
    line = log_output.string.lines.last
    JSON.parse(line)
  end

  def test_logs_task_start_with_user_input_and_strategy_class_name
    logger, log_output = make_logger
    make_subscriber(logger).subscribe(listener)

    listener.emit(Rixie::Event::TaskStart.new(user_input: "Hello", strategy: Rixie::Strategy::Simple.new))

    record = last_record(log_output)
    assert_equal "task_start", record["type"]
    assert_equal "Hello", record["payload"]["user_input"]
    assert_equal "Rixie::Strategy::Simple", record["payload"]["strategy"]
  end

  def test_logs_task_end_with_status
    logger, log_output = make_logger
    make_subscriber(logger).subscribe(listener)

    listener.emit(Rixie::Event::TaskEnd.new(output: "done", status: "completed"))

    record = last_record(log_output)
    assert_equal "task_end", record["type"]
    assert_equal "completed", record["payload"]["status"]
  end

  def test_logs_run_start_with_user_input
    logger, log_output = make_logger
    make_subscriber(logger).subscribe(listener)

    listener.emit(Rixie::Event::RunStart.new(user_input: "Hi"))

    record = last_record(log_output)
    assert_equal "run_start", record["type"]
    assert_equal "Hi", record["payload"]["user_input"]
  end

  def test_logs_run_end_with_status
    logger, log_output = make_logger
    make_subscriber(logger).subscribe(listener)

    listener.emit(Rixie::Event::RunEnd.new(output: "done", status: "completed"))

    record = last_record(log_output)
    assert_equal "run_end", record["type"]
    assert_equal "completed", record["payload"]["status"]
  end

  def test_logs_compression_start_with_entry_count_and_keep_recent
    logger, log_output = make_logger
    make_subscriber(logger).subscribe(listener)

    listener.emit(Rixie::Event::CompressionStart.new(entry_count: 12, keep_recent: 4))

    record = last_record(log_output)
    assert_equal "compression_start", record["type"]
    assert_equal 12, record["payload"]["entry_count"]
    assert_equal 4, record["payload"]["keep_recent"]
  end

  def test_logs_compression_end_with_status_and_entry_count
    logger, log_output = make_logger
    make_subscriber(logger).subscribe(listener)

    listener.emit(Rixie::Event::CompressionEnd.new(status: "completed", entry_count: 5))

    record = last_record(log_output)
    assert_equal "compression_end", record["type"]
    assert_equal "completed", record["payload"]["status"]
    assert_equal 5, record["payload"]["entry_count"]
  end

  def test_logs_llm_call_start_with_step_count
    logger, log_output = make_logger
    make_subscriber(logger).subscribe(listener)

    listener.emit(Rixie::Event::LlmCallStart.new(step_count: 3))

    record = last_record(log_output)
    assert_equal "llm_call_start", record["type"]
    assert_equal 3, record["payload"]["step_count"]
  end

  def test_logs_tool_call_start_with_tool_call_fields
    logger, log_output = make_logger
    make_subscriber(logger).subscribe(listener)

    tool_call = Rixie::LLM::ToolCall.new(id: "c1", name: "get_weather", arguments: {"city" => "Tokyo"})
    listener.emit(Rixie::Event::ToolCallStart.new(tool_call: tool_call))

    record = last_record(log_output)
    assert_equal "tool_call_start", record["type"]
    assert_equal "c1", record["payload"]["tool_call"]["id"]
    assert_equal "get_weather", record["payload"]["tool_call"]["name"]
    assert_equal({"city" => "Tokyo"}, record["payload"]["tool_call"]["arguments"])
  end

  def test_logs_tool_call_end_with_success_result
    logger, log_output = make_logger
    make_subscriber(logger).subscribe(listener)

    tool_call = Rixie::LLM::ToolCall.new(id: "c1", name: "get_weather", arguments: {})
    result = Rixie::ToolExecutor::Result.new(tool_call_id: "c1", content: "sunny", error: nil)
    listener.emit(Rixie::Event::ToolCallEnd.new(tool_call: tool_call, result: result))

    record = last_record(log_output)
    assert_equal "tool_call_end", record["type"]
    assert_equal "c1", record["payload"]["tool_call"]["id"]
    assert_equal "get_weather", record["payload"]["tool_call"]["name"]
    assert_equal "sunny", record["payload"]["result"]["content"]
    assert_nil record["payload"]["result"]["error"]
  end

  def test_logs_tool_call_end_with_error_message
    logger, log_output = make_logger
    make_subscriber(logger).subscribe(listener)

    tool_call = Rixie::LLM::ToolCall.new(id: "c1", name: "broken", arguments: {})
    error = RuntimeError.new("boom")
    result = Rixie::ToolExecutor::Result.new(tool_call_id: "c1", content: "Error: boom", error: error)
    listener.emit(Rixie::Event::ToolCallEnd.new(tool_call: tool_call, result: result))

    record = last_record(log_output)
    assert_equal "boom", record["payload"]["result"]["error"]
  end

  def test_logs_finished_with_content
    logger, log_output = make_logger
    make_subscriber(logger).subscribe(listener)

    listener.emit(Rixie::Event::Finished.new(content: "All done"))

    record = last_record(log_output)
    assert_equal "finished", record["type"]
    assert_equal "All done", record["payload"]["content"]
  end

  def test_record_includes_envelope_metadata
    logger, log_output = make_logger
    make_subscriber(logger).subscribe(listener)

    listener.emit(Rixie::Event::Finished.new(content: nil))

    record = last_record(log_output)
    assert_kind_of Integer, record["seq"]
    assert_kind_of String, record["event_id"]
    assert_kind_of String, record["occurred_at"]
    assert record.key?("session_id")
    assert record.key?("task_id")
    assert record.key?("run_id")
  end

  def test_emits_one_json_object_per_line
    logger, log_output = make_logger
    make_subscriber(logger).subscribe(listener)

    listener.emit(Rixie::Event::LlmCallStart.new(step_count: 1))
    listener.emit(Rixie::Event::Finished.new(content: "x"))

    lines = log_output.string.lines.map(&:strip).reject(&:empty?)
    assert_equal 2, lines.size
    lines.each { |line| assert_kind_of Hash, JSON.parse(line) }
  end

  def test_info_level_logger_filters_out_debug_events
    log_output = StringIO.new
    logger = ::Logger.new(log_output)
    logger.formatter = ->(_sev, _time, _prog, msg) { "#{msg}\n" }
    logger.level = ::Logger::INFO
    make_subscriber(logger).subscribe(listener)

    listener.emit(Rixie::Event::LlmCallStart.new(step_count: 1))
    tool_call = Rixie::LLM::ToolCall.new(id: "c1", name: "x", arguments: {})
    listener.emit(Rixie::Event::ToolCallStart.new(tool_call: tool_call))

    assert_empty log_output.string
  end

  def test_info_level_logger_emits_tool_call_end_when_errored
    log_output = StringIO.new
    logger = ::Logger.new(log_output)
    logger.formatter = ->(sev, _time, _prog, msg) { "#{sev} #{msg}\n" }
    logger.level = ::Logger::INFO
    make_subscriber(logger).subscribe(listener)

    tool_call = Rixie::LLM::ToolCall.new(id: "c1", name: "broken", arguments: {})
    result = Rixie::ToolExecutor::Result.new(tool_call_id: "c1", content: "Error: boom", error: RuntimeError.new("boom"))
    listener.emit(Rixie::Event::ToolCallEnd.new(tool_call: tool_call, result: result))

    line = log_output.string.lines.last
    assert_match "WARN", line
    payload = line.split(" ", 2).last
    record = JSON.parse(payload)
    assert_equal "tool_call_end", record["type"]
  end

  def test_uses_injected_logger_not_global_config
    global_log = StringIO.new
    Rixie.config.logger = ::Logger.new(global_log)

    injected_log = StringIO.new
    injected_logger = ::Logger.new(injected_log)
    injected_logger.formatter = ->(_sev, _time, _prog, msg) { "#{msg}\n" }

    sub = Rixie::Subscribers::JsonLogger.new(logger: injected_logger)
    sub.subscribe(listener)
    listener.emit(Rixie::Event::TaskEnd.new(output: nil, status: "completed"))

    record = JSON.parse(injected_log.string.lines.last)
    assert_equal "task_end", record["type"]
    assert_empty global_log.string
  end
end
