# frozen_string_literal: true

require "test_helper"
require "openai"
require "rixie/llm/adapter/openai"

class OpenAIAdapterTest < Minitest::Test
  EMPTY_RESULT = Struct.new(:choices).new([])

  def build_adapter(max_tokens: nil, temperature: nil)
    Rixie::LLM::Adapter::OpenAI.new(
      model: "gpt-4o",
      base_url: "https://api.openai.com/v1",
      api_key: "test",
      max_tokens: max_tokens,
      temperature: temperature
    )
  end

  def stub_client(adapter)
    captured = nil
    fake_completions = Object.new
    fake_completions.define_singleton_method(:create) { |**params|
      captured = params
      EMPTY_RESULT
    }
    fake_chat = Object.new
    fake_chat.define_singleton_method(:completions) { fake_completions }
    adapter.instance_variable_get(:@client).define_singleton_method(:chat) { fake_chat }
    -> { captured }
  end

  # Builds a fake ChatCompletionChunk from a hash: { content:, tool_calls: [...] }
  # tool_calls entry: { index:, id:, name:, arguments: }
  def make_chunk(content: nil, tool_calls: nil, finish_reason: nil)
    tc_structs = tool_calls&.map do |tc|
      fn = Struct.new(:name, :arguments).new(tc[:name], tc[:arguments])
      Struct.new(:index, :id, :function).new(tc[:index], tc[:id], fn)
    end
    delta = Struct.new(:content, :tool_calls).new(content, tc_structs)
    choice = Struct.new(:delta, :finish_reason).new(delta, finish_reason)
    Struct.new(:choices).new([choice])
  end

  def stub_stream_client(adapter, chunks:)
    fake_completions = Object.new
    fake_completions.define_singleton_method(:stream_raw) { |**| chunks }
    fake_chat = Object.new
    fake_chat.define_singleton_method(:completions) { fake_completions }
    adapter.instance_variable_get(:@client).define_singleton_method(:chat) { fake_chat }
  end

  def test_chat_encodes_tool_objects_to_openai_format
    adapter = build_adapter
    get_captured = stub_client(adapter)
    tool = Rixie::Tool.new(
      name: "get_weather",
      description: "Get weather for a city",
      input_schema: {type: "object", properties: {city: {type: "string"}}},
      call: ->(_) { "sunny" }
    )
    adapter.chat([], tools: [tool])
    tools = get_captured.call[:tools]
    assert_equal 1, tools.size
    assert_equal "function", tools.first[:type]
    assert_equal "get_weather", tools.first[:function][:name]
    assert_equal "Get weather for a city", tools.first[:function][:description]
    assert_equal tool.input_schema, tools.first[:function][:parameters]
  end

  def test_chat_does_not_include_max_tokens_when_nil
    adapter = build_adapter
    get_captured = stub_client(adapter)
    adapter.chat([], tools: [])
    refute get_captured.call.key?(:max_tokens)
  end

  def test_chat_includes_max_tokens_when_set
    adapter = build_adapter(max_tokens: 1024)
    get_captured = stub_client(adapter)
    adapter.chat([], tools: [])
    assert_equal 1024, get_captured.call[:max_tokens]
  end

  def test_chat_does_not_include_temperature_when_nil
    adapter = build_adapter
    get_captured = stub_client(adapter)
    adapter.chat([], tools: [])
    refute get_captured.call.key?(:temperature)
  end

  def test_chat_includes_temperature_when_set
    adapter = build_adapter(temperature: 0.5)
    get_captured = stub_client(adapter)
    adapter.chat([], tools: [])
    assert_equal 0.5, get_captured.call[:temperature]
  end

  def test_stream_emits_event_token_for_each_text_delta
    adapter = build_adapter
    chunks = [
      make_chunk(content: "Hello"),
      make_chunk(content: " world")
    ]
    stub_stream_client(adapter, chunks: chunks)

    tokens = []
    adapter.stream([], tools: []) { |e| tokens << e }

    assert_equal 2, tokens.size
    assert_instance_of Rixie::Event::Token, tokens[0]
    assert_equal "Hello", tokens[0].delta
    assert_equal " world", tokens[1].delta
  end

  def test_stream_does_not_emit_for_tool_call_deltas
    adapter = build_adapter
    chunks = [
      make_chunk(tool_calls: [{index: 0, id: "c1", name: "search", arguments: "{}"}])
    ]
    stub_stream_client(adapter, chunks: chunks)

    tokens = []
    adapter.stream([], tools: []) { |e| tokens << e }

    assert_empty tokens
  end

  def test_stream_accumulates_tool_call_deltas_correctly
    adapter = build_adapter
    chunks = [
      make_chunk(tool_calls: [{index: 0, id: "c1", name: "get_w", arguments: ""}]),
      make_chunk(tool_calls: [{index: 0, id: "", name: "eather", arguments: "{\"city\""}]),
      make_chunk(tool_calls: [{index: 0, id: "", name: "", arguments: ": \"Tokyo\"}"}])
    ]
    stub_stream_client(adapter, chunks: chunks)

    response = adapter.stream([], tools: []) { |_| }

    assert response.has_tool_calls?
    tc = response.tool_calls.first
    assert_instance_of Rixie::LLM::ToolCall, tc
    assert_equal "c1", tc.id
    assert_equal "get_weather", tc.name
    assert_equal({"city" => "Tokyo"}, tc.arguments)
  end

  def test_stream_returns_completed_response
    adapter = build_adapter
    chunks = [
      make_chunk(content: "Hello"),
      make_chunk(content: " there")
    ]
    stub_stream_client(adapter, chunks: chunks)

    response = adapter.stream([], tools: []) { |_| }

    assert_instance_of Rixie::LLM::Response, response
    assert_equal "Hello there", response.content
    refute response.has_tool_calls?
  end

  def test_stream_captures_finish_reason_from_final_chunk
    adapter = build_adapter
    chunks = [
      make_chunk(content: "cut off..."),
      make_chunk(finish_reason: "length")
    ]
    stub_stream_client(adapter, chunks: chunks)

    response = adapter.stream([], tools: []) { |_| }

    assert_equal "length", response.finish_reason
  end
end
