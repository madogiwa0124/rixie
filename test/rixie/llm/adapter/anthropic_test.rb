# frozen_string_literal: true

require "test_helper"
require "anthropic"
require "rixie/llm/adapter/anthropic"

class AnthropicAdapterTest < Minitest::Test
  def build_adapter(max_tokens: nil, temperature: nil)
    Rixie::LLM::Adapter::Anthropic.new(
      model: "claude-opus-4-5",
      base_url: "https://api.anthropic.com",
      api_key: "test",
      max_tokens: max_tokens,
      temperature: temperature
    )
  end

  def test_chat_uses_default_max_tokens_when_nil
    captured = nil
    adapter = build_adapter
    adapter.instance_variable_get(:@client).define_singleton_method(:messages) { |parameters:|
      captured = parameters
      {}
    }
    adapter.chat([], tools: [])

    assert_equal Rixie::LLM::Adapter::Anthropic::DEFAULT_MAX_TOKENS, captured[:max_tokens]
  end

  def test_chat_uses_specified_max_tokens
    captured = nil
    adapter = build_adapter(max_tokens: 2048)
    adapter.instance_variable_get(:@client).define_singleton_method(:messages) { |parameters:|
      captured = parameters
      {}
    }
    adapter.chat([], tools: [])

    assert_equal 2048, captured[:max_tokens]
  end

  def test_chat_does_not_include_temperature_when_nil
    captured = nil
    adapter = build_adapter
    adapter.instance_variable_get(:@client).define_singleton_method(:messages) { |parameters:|
      captured = parameters
      {}
    }
    adapter.chat([], tools: [])

    refute captured.key?(:temperature)
  end

  def test_chat_includes_temperature_when_set
    captured = nil
    adapter = build_adapter(temperature: 0.0)
    adapter.instance_variable_get(:@client).define_singleton_method(:messages) { |parameters:|
      captured = parameters
      {}
    }
    adapter.chat([], tools: [])

    assert_equal 0.0, captured[:temperature]
  end
end
