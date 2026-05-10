# frozen_string_literal: true

require "test_helper"

class ClientTest < Minitest::Test
  def setup
    super
    Rixie.configure do |config|
      config.register_provider("dummy",
        adapter: DummyAdapter,
        base_url: "http://localhost",
        api_key: "test")
    end
  end

  def test_chat_delegates_to_resolved_adapter
    finish_response = Rixie::LLM::Response.new(
      raw: {"choices" => [{"message" => {"content" => "Hello!", "tool_calls" => nil}}]},
      provider: :openai
    )
    dummy = DummyAdapter.new([finish_response])

    Rixie.configure do |config|
      config.register_provider("injected",
        adapter: dummy.class,
        base_url: "http://localhost",
        api_key: "test")
    end

    # Inject the dummy adapter directly via a custom provider using a wrapper class
    # that returns our pre-configured dummy.
    wrapper = Class.new do
      define_method(:initialize) { |**| }
      define_method(:chat) { |messages, tools:| dummy.chat(messages, tools: tools) }
    end

    Rixie.configure do |config|
      config.register_provider("wrapper",
        adapter: wrapper,
        base_url: "http://localhost",
        api_key: "test")
    end

    client = Rixie::LLM::Client.new(model: "test-model", provider: "wrapper")
    result = client.chat([{role: "user", content: "Hi"}], tools: [])

    assert_equal "Hello!", result.content
  end

  def test_dummy_adapter_raises_when_exhausted
    dummy = DummyAdapter.new([])
    assert_raises(RuntimeError) { dummy.chat([], tools: []) }
  end
end
