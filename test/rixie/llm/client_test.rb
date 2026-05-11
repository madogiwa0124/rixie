# frozen_string_literal: true

require "test_helper"

class ClientTest < Minitest::Test
  def finish_response(content: "Hello!")
    {"choices" => [{"message" => {"content" => content, "tool_calls" => nil}}]}
  end

  def make_dummy_client(responses, stream: false)
    adapter = Rixie::LLM::Adapter::Dummy.new(responses)
    Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter, stream: stream)
  end

  def test_call_delegates_to_resolved_adapter
    client = make_dummy_client([finish_response])
    result = client.call([{role: "user", content: "Hi"}], tools: [])
    assert_equal "Hello!", result.content
  end

  def test_dummy_adapter_raises_when_exhausted
    dummy = Rixie::LLM::Adapter::Dummy.new([])
    assert_raises(RuntimeError) { dummy.chat([], tools: []) }
  end

  def test_call_uses_adapter_chat_when_stream_is_false
    client = make_dummy_client([finish_response])
    result = client.call([], tools: [])
    assert_equal "Hello!", result.content
  end

  def test_call_uses_adapter_stream_when_stream_is_true
    client = make_dummy_client([finish_response(content: "streamed")], stream: true)
    result = client.call([], tools: []) {}
    assert_equal "streamed", result.content
  end

  def test_call_passes_block_to_stream_adapter
    tokens = []
    client = make_dummy_client([finish_response(content: "hi")], stream: true)
    client.call([], tools: []) { |e| tokens << e.delta if e.is_a?(Rixie::Event::Token) }
    assert_equal ["hi"], tokens
  end

  def test_model_and_provider_are_readable
    client = Rixie::LLM::Client.new(
      model: "gpt-4o", provider: "openai",
      adapter: Rixie::LLM::Adapter::Dummy.new([])
    )
    assert_equal "gpt-4o", client.model
    assert_equal "openai", client.provider
  end
end
