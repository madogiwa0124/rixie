# frozen_string_literal: true

require "test_helper"
require "anthropic"
require "rixie/llm/adapter/anthropic"

class AnthropicAdapterTest < Minitest::Test
  ContentBlockStartEvent = Struct.new(:type, :content_block, :delta)
  ContentBlockDeltaEvent = Struct.new(:type, :content_block, :delta)
  TextContentBlock = Struct.new(:type)
  ToolUseContentBlock = Struct.new(:type, :id, :name)
  TextDelta = Struct.new(:type, :text, :partial_json)
  InputJsonDelta = Struct.new(:type, :text, :partial_json)

  def build_adapter(max_tokens: nil, temperature: nil)
    Rixie::LLM::Adapter::Anthropic.new(
      model: "claude-opus-4-5",
      base_url: "https://api.anthropic.com",
      api_key: "test",
      max_tokens: max_tokens,
      temperature: temperature
    )
  end

  def stub_messages(adapter, &impl)
    adapter.instance_variable_get(:@client).define_singleton_method(:messages, &impl)
  end

  def test_chat_uses_default_max_tokens_when_nil
    captured = nil
    adapter = build_adapter
    stub_messages(adapter) { |parameters:, &block| captured = parameters; {} }
    adapter.chat([], tools: [])

    assert_equal Rixie::LLM::Adapter::Anthropic::DEFAULT_MAX_TOKENS, captured[:max_tokens]
  end

  def test_chat_uses_specified_max_tokens
    captured = nil
    adapter = build_adapter(max_tokens: 2048)
    stub_messages(adapter) { |parameters:, &block| captured = parameters; {} }
    adapter.chat([], tools: [])

    assert_equal 2048, captured[:max_tokens]
  end

  def test_chat_does_not_include_temperature_when_nil
    captured = nil
    adapter = build_adapter
    stub_messages(adapter) { |parameters:, &block| captured = parameters; {} }
    adapter.chat([], tools: [])

    refute captured.key?(:temperature)
  end

  def test_chat_includes_temperature_when_set
    captured = nil
    adapter = build_adapter(temperature: 0.0)
    stub_messages(adapter) { |parameters:, &block| captured = parameters; {} }
    adapter.chat([], tools: [])

    assert_equal 0.0, captured[:temperature]
  end

  def test_stream_emits_event_token_for_text_delta_events
    adapter = build_adapter
    events = [
      ContentBlockDeltaEvent.new("content_block_delta", nil, TextDelta.new("text_delta", "Hello", nil)),
      ContentBlockDeltaEvent.new("content_block_delta", nil, TextDelta.new("text_delta", " world", nil))
    ]
    stub_messages(adapter) { |parameters:, &block| events.each { |e| block.call(e) }; {} }

    tokens = []
    adapter.stream([], tools: []) { |e| tokens << e }

    assert_equal 2, tokens.size
    assert_instance_of Rixie::Event::Token, tokens[0]
    assert_equal "Hello", tokens[0].delta
    assert_equal " world", tokens[1].delta
  end

  def test_stream_accumulates_input_json_delta_for_tool_calls
    adapter = build_adapter
    events = [
      ContentBlockStartEvent.new("content_block_start", ToolUseContentBlock.new("tool_use", "c1", "get_weather"), nil),
      ContentBlockDeltaEvent.new("content_block_delta", nil, InputJsonDelta.new("input_json_delta", nil, "{\"city\":")),
      ContentBlockDeltaEvent.new("content_block_delta", nil, InputJsonDelta.new("input_json_delta", nil, " \"Tokyo\"}"))
    ]
    stub_messages(adapter) { |parameters:, &block| events.each { |e| block.call(e) }; {} }

    tokens = []
    response = adapter.stream([], tools: []) { |e| tokens << e }

    assert_empty tokens
    assert response.has_tool_calls?
    tc = response.tool_calls.first
    assert_equal "c1", tc["id"]
    assert_equal "get_weather", tc["function"]["name"]
    assert_equal "{\"city\": \"Tokyo\"}", tc["function"]["arguments"]
  end

  def test_stream_returns_completed_response
    adapter = build_adapter
    events = [
      ContentBlockDeltaEvent.new("content_block_delta", nil, TextDelta.new("text_delta", "Hello", nil)),
      ContentBlockDeltaEvent.new("content_block_delta", nil, TextDelta.new("text_delta", " there", nil))
    ]
    stub_messages(adapter) { |parameters:, &block| events.each { |e| block.call(e) }; {} }

    response = adapter.stream([], tools: []) { |_| }

    assert_instance_of Rixie::LLM::Response, response
    assert_equal "Hello there", response.content
    refute response.has_tool_calls?
  end
end
