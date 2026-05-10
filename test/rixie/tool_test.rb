# frozen_string_literal: true

require "test_helper"

class ToolTest < Minitest::Test
  def make_tool(result: "ok")
    Rixie::Tool.new(
      name: "get_weather",
      description: "Get the weather for a location",
      input_schema: {type: "object", properties: {location: {type: "string"}}, required: ["location"]},
      call: ->(args) { result }
    )
  end

  def test_to_definition_returns_openai_compatible_format
    tool = make_tool
    defn = tool.to_definition
    assert_equal "function", defn[:type]
    assert_equal "get_weather", defn[:function][:name]
    assert_equal "Get the weather for a location", defn[:function][:description]
    assert_equal tool.input_schema, defn[:function][:parameters]
  end

  def test_call_executes_lambda_with_arguments
    received = nil
    tool = Rixie::Tool.new(
      name: "echo",
      description: "echo",
      input_schema: {},
      call: ->(args) {
        received = args
        "done"
      }
    )
    tool.call({"input" => "hello"})
    assert_equal({"input" => "hello"}, received)
  end

  def test_call_returns_result_of_lambda
    tool = make_tool(result: "sunny")
    assert_equal "sunny", tool.call({})
  end
end
