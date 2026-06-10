# frozen_string_literal: true

require "test_helper"

class SubscribersEventSeverityTest < Minitest::Test
  def severity_for(event)
    Rixie::Subscribers::EventSeverity.for(event)
  end

  def test_lifecycle_events_are_info
    assert_equal :info, severity_for(Rixie::Event::TaskStart.new(user_input: "x", strategy: Rixie::Strategy::Simple.new))
    assert_equal :info, severity_for(Rixie::Event::TaskEnd.new(output: nil, status: "completed"))
    assert_equal :info, severity_for(Rixie::Event::RunStart.new(user_input: "x"))
    assert_equal :info, severity_for(Rixie::Event::RunEnd.new(output: nil, status: "completed"))
    assert_equal :info, severity_for(Rixie::Event::Finished.new(content: "x"))
  end

  def test_compression_start_is_info
    assert_equal :info, severity_for(Rixie::Event::CompressionStart.new(entry_count: 10, keep_recent: 3))
  end

  def test_compression_end_completed_is_info
    assert_equal :info, severity_for(Rixie::Event::CompressionEnd.new(status: "completed", entry_count: 5))
  end

  def test_compression_end_failed_is_warn
    assert_equal :warn, severity_for(Rixie::Event::CompressionEnd.new(status: "failed", entry_count: 5))
  end

  def test_llm_call_start_is_debug
    assert_equal :debug, severity_for(Rixie::Event::LlmCallStart.new(step_count: 1, model: "gpt-4o", provider: "openai"))
  end

  def test_llm_call_end_is_debug
    assert_equal :debug, severity_for(Rixie::Event::LlmCallEnd.new(step_count: 1, usage: {input_tokens: 10, output_tokens: 5}, finish_reason: "stop"))
  end

  def test_tool_call_start_is_debug
    tc = Rixie::LLM::ToolCall.new(id: "c1", name: "x", arguments: {})
    assert_equal :debug, severity_for(Rixie::Event::ToolCallStart.new(tool_call: tc))
  end

  def test_tool_call_end_success_is_debug
    tc = Rixie::LLM::ToolCall.new(id: "c1", name: "x", arguments: {})
    result = Rixie::ToolExecutor::Result.new(tool_call_id: "c1", content: "ok", error: nil)
    assert_equal :debug, severity_for(Rixie::Event::ToolCallEnd.new(tool_call: tc, result: result))
  end

  def test_tool_call_end_error_is_warn
    tc = Rixie::LLM::ToolCall.new(id: "c1", name: "x", arguments: {})
    result = Rixie::ToolExecutor::Result.new(tool_call_id: "c1", content: "Error: boom", error: RuntimeError.new("boom"))
    assert_equal :warn, severity_for(Rixie::Event::ToolCallEnd.new(tool_call: tc, result: result))
  end
end
