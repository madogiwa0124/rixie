# frozen_string_literal: true

require "test_helper"

class ResolverTest < Minitest::Test
  Resolver = Rixie::LLM::Client::Resolver

  def test_resolves_builtin_openai_provider
    adapter = Resolver.resolve(model: "gpt-4o", provider: "openai")
    assert_instance_of Rixie::LLM::Adapter::OpenAI, adapter
  end

  def test_resolves_builtin_anthropic_provider
    adapter = Resolver.resolve(model: "claude-3-5-sonnet-20241022", provider: "anthropic")
    assert_instance_of Rixie::LLM::Adapter::Anthropic, adapter
  end

  def test_resolves_custom_provider_registered_via_config
    Rixie.configure do |config|
      config.register_provider("test_provider",
        adapter: DummyAdapter,
        base_url: "http://localhost",
        api_key: "test")
    end

    adapter = Resolver.resolve(model: "test-model", provider: "test_provider")
    assert_instance_of DummyAdapter, adapter
  end

  def test_custom_provider_takes_precedence_over_builtin
    Rixie.configure do |config|
      config.register_provider("openai",
        adapter: DummyAdapter,
        base_url: "https://my-proxy.internal/v1",
        api_key: "custom")
    end

    adapter = Resolver.resolve(model: "gpt-4o", provider: "openai")
    assert_instance_of DummyAdapter, adapter
  end

  def test_raises_no_provider_error_when_no_provider_and_no_default
    assert_raises(Rixie::NoProviderError) do
      Resolver.resolve(model: "gpt-4o")
    end
  end

  def test_raises_unknown_provider_error_for_unknown_name
    assert_raises(Rixie::UnknownProviderError) do
      Resolver.resolve(model: "gpt-4o", provider: "nonexistent")
    end
  end

  def test_raises_no_provider_error_when_provider_is_nil
    assert_raises(Rixie::NoProviderError) do
      Resolver.resolve(model: "gpt-4o", provider: nil)
    end
  end
end
