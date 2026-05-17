# frozen_string_literal: true

require "test_helper"

class ToolExecutorTest < Minitest::Test
  def make_tool(name:, result:, return_direct: false)
    Rixie::Tool.new(
      name: name,
      description: "desc",
      input_schema: {},
      call: ->(_args) { result },
      return_direct: return_direct
    )
  end

  def make_tool_call(id:, name:, arguments: {})
    Rixie::LLM::ToolCall.new(id: id, name: name, arguments: arguments)
  end

  def test_execute_calls_matching_tool_and_returns_result
    executor = Rixie::ToolExecutor.new(tools: [make_tool(name: "greet", result: "hello")])
    result = executor.execute(make_tool_call(id: "call_1", name: "greet"))
    assert_instance_of Rixie::ToolExecutor::Result, result
    assert_equal "call_1", result.tool_call_id
    assert_equal "hello", result.content
    assert result.success?
    refute result.error?
  end

  def test_execute_coerces_result_to_string
    executor = Rixie::ToolExecutor.new(tools: [make_tool(name: "count", result: 42)])
    result = executor.execute(make_tool_call(id: "call_2", name: "count"))
    assert_equal "42", result.content
  end

  def test_definitions_returns_empty_array_when_no_tools
    executor = Rixie::ToolExecutor.new
    assert_equal [], executor.definitions
  end

  def test_definitions_returns_tool_objects
    tool = make_tool(name: "get_weather", result: "sunny")
    executor = Rixie::ToolExecutor.new(tools: [tool])
    defns = executor.definitions
    assert_equal 1, defns.size
    assert_instance_of Rixie::Tool, defns.first
    assert_equal "get_weather", defns.first.name
  end

  def test_return_direct_returns_false_when_no_tool_is_return_direct
    executor = Rixie::ToolExecutor.new(tools: [make_tool(name: "greet", result: "hello")])
    calls = [make_tool_call(id: "c1", name: "greet")]
    refute executor.return_direct?(calls)
  end

  def test_return_direct_returns_true_when_called_tool_is_return_direct
    executor = Rixie::ToolExecutor.new(tools: [make_tool(name: "stop", result: "done", return_direct: true)])
    calls = [make_tool_call(id: "c1", name: "stop")]
    assert executor.return_direct?(calls)
  end

  def test_return_direct_returns_true_when_any_called_tool_is_return_direct
    executor = Rixie::ToolExecutor.new(tools: [
      make_tool(name: "normal", result: "ok"),
      make_tool(name: "stop", result: "done", return_direct: true)
    ])
    calls = [make_tool_call(id: "c1", name: "normal"), make_tool_call(id: "c2", name: "stop")]
    assert executor.return_direct?(calls)
  end

  def test_return_direct_returns_false_for_unknown_tool
    executor = Rixie::ToolExecutor.new(tools: [])
    calls = [make_tool_call(id: "c1", name: "unknown")]
    refute executor.return_direct?(calls)
  end

  def test_raises_tool_not_found_error_when_tool_not_found
    executor = Rixie::ToolExecutor.new(tools: [])
    assert_raises(Rixie::ToolNotFoundError) do
      executor.execute(make_tool_call(id: "c1", name: "missing"))
    end
  end

  def test_execute_returns_error_result_when_tool_raises
    boom = Rixie::Tool.new(name: "boom", description: "d", input_schema: {}, call: ->(_) { raise "kaboom" })
    executor = Rixie::ToolExecutor.new(tools: [boom])
    result = executor.execute(make_tool_call(id: "c1", name: "boom"))
    assert_instance_of Rixie::ToolExecutor::Result, result
    assert result.error?
    assert_equal "Error: kaboom", result.content
    assert_equal "kaboom", result.error.message
  end
end
