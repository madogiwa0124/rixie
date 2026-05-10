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
    fake_completions.define_singleton_method(:create) { |**params| captured = params; EMPTY_RESULT }
    fake_chat = Object.new
    fake_chat.define_singleton_method(:completions) { fake_completions }
    adapter.instance_variable_get(:@client).define_singleton_method(:chat) { fake_chat }
    -> { captured }
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
end
