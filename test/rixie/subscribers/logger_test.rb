# frozen_string_literal: true

require "test_helper"

class SubscribersLoggerTest < Minitest::Test
  def make_logger
    log_output = StringIO.new
    [::Logger.new(log_output), log_output]
  end

  def make_subscriber(logger)
    Rixie::Subscribers::Logger.new(logger: logger)
  end

  def listener
    @listener ||= Rixie::EventListener.new
  end

  def test_subscribe_registers_handlers_on_listener
    logger, _ = make_logger
    sub = make_subscriber(logger)
    sub.subscribe(listener)
    listener.emit(Rixie::Event::TaskStart.new(user_input: "Hi", strategy: Object.new))
  end

  def test_logs_task_start_with_user_input_and_strategy_class_name
    logger, log_output = make_logger
    sub = make_subscriber(logger)
    sub.subscribe(listener)

    strategy = Rixie::Strategy::Simple.new
    listener.emit(Rixie::Event::TaskStart.new(user_input: "Hello", strategy: strategy))

    assert_match "[Task] started:", log_output.string
    assert_match '"Hello"', log_output.string
    assert_match "Rixie::Strategy::Simple", log_output.string
  end

  def test_logs_task_end_with_status
    logger, log_output = make_logger
    sub = make_subscriber(logger)
    sub.subscribe(listener)

    listener.emit(Rixie::Event::TaskEnd.new(output: "done", status: "completed"))

    assert_match "[Task] completed", log_output.string
  end

  def test_logs_run_start_with_user_input
    logger, log_output = make_logger
    sub = make_subscriber(logger)
    sub.subscribe(listener)

    listener.emit(Rixie::Event::RunStart.new(user_input: "Hello"))

    assert_match "[Run] started:", log_output.string
    assert_match '"Hello"', log_output.string
  end

  def test_logs_run_end_with_status
    logger, log_output = make_logger
    sub = make_subscriber(logger)
    sub.subscribe(listener)

    listener.emit(Rixie::Event::RunEnd.new(output: "done", status: "completed"))

    assert_match "[Run] completed", log_output.string
  end

  def test_logs_llm_call_start_with_step_count
    logger, log_output = make_logger
    sub = make_subscriber(logger)
    sub.subscribe(listener)

    listener.emit(Rixie::Event::LlmCallStart.new(step_count: 2))

    assert_match "[Agent] llm_call #2", log_output.string
  end

  def test_logs_tool_call_start_with_tool_name_and_arguments
    logger, log_output = make_logger
    sub = make_subscriber(logger)
    sub.subscribe(listener)

    tool_call = Rixie::LLM::ToolCall.new(id: "c1", name: "get_weather", arguments: {city: "Tokyo"})
    listener.emit(Rixie::Event::ToolCallStart.new(tool_call: tool_call))

    assert_match "[Agent] tool_call: get_weather", log_output.string
  end

  def test_logs_tool_call_end_with_result_content
    logger, log_output = make_logger
    sub = make_subscriber(logger)
    sub.subscribe(listener)

    tool_call = Rixie::LLM::ToolCall.new(id: "c1", name: "get_weather", arguments: {})
    result = Rixie::ToolExecutor::Result.new(tool_call_id: "c1", content: "sunny", error: nil)
    listener.emit(Rixie::Event::ToolCallEnd.new(tool_call: tool_call, result: result))

    assert_match "[Agent] tool_result:", log_output.string
    assert_match '"sunny"', log_output.string
  end

  def test_logs_finished_with_content
    logger, log_output = make_logger
    sub = make_subscriber(logger)
    sub.subscribe(listener)

    listener.emit(Rixie::Event::Finished.new(content: "All done"))

    assert_match "[Agent] finish:", log_output.string
    assert_match '"All done"', log_output.string
  end

  def test_uses_injected_logger_not_global_config
    global_log = StringIO.new
    Rixie.config.logger = ::Logger.new(global_log)

    injected_log = StringIO.new
    injected_logger = ::Logger.new(injected_log)

    sub = Rixie::Subscribers::Logger.new(logger: injected_logger)
    sub.subscribe(listener)
    listener.emit(Rixie::Event::TaskEnd.new(output: nil, status: "completed"))

    assert_match "[Task] completed", injected_log.string
    refute_match "[Task]", global_log.string
  end
end
