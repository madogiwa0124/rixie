# frozen_string_literal: true

require "test_helper"
require "openai"
require "rixie/llm/adapter/openai"

class OpenAIAdapterTest < Minitest::Test
  EMPTY_RESULT = Struct.new(:choices).new([])

  def build_adapter(temperature: nil, provider_params: nil, null_content_fallback: false)
    Rixie::LLM::Adapter::OpenAI.new(
      model: "gpt-4o",
      base_url: "https://api.openai.com/v1",
      api_key: "test",
      temperature: temperature,
      provider_params: provider_params,
      null_content_fallback: null_content_fallback
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

  def user_msg(content)
    Rixie::Message::User.new(content: content)
  end

  def test_chat_passes_string_user_content_through_unchanged
    adapter = build_adapter
    get_captured = stub_client(adapter)
    adapter.chat([user_msg("hello")], tools: [])
    msg = get_captured.call[:messages].first
    assert_equal "user", msg[:role]
    assert_equal "hello", msg[:content]
  end

  # Content blocks reach the adapter already validated and canonicalized to
  # string keys by Rixie::Input. The adapter is pure wire translation; block
  # validation is covered by InputTest, not here.
  def test_chat_encodes_array_user_content_with_text_and_image
    adapter = build_adapter
    get_captured = stub_client(adapter)
    content = [
      {"type" => "text", "text" => "What's in this image?"},
      {"type" => "image", "source" => {"type" => "base64", "media_type" => "image/png", "data" => "QUJD"}}
    ]
    adapter.chat([user_msg(content)], tools: [])
    encoded = get_captured.call[:messages].first[:content]
    assert_equal({type: "text", text: "What's in this image?"}, encoded[0])
    assert_equal "image_url", encoded[1][:type]
    assert_equal "data:image/png;base64,QUJD", encoded[1][:image_url][:url]
  end

  def test_chat_encodes_image_only_content
    adapter = build_adapter
    get_captured = stub_client(adapter)
    content = [{"type" => "image", "source" => {"type" => "base64", "media_type" => "image/jpeg", "data" => "ENC"}}]
    adapter.chat([user_msg(content)], tools: [])
    encoded = get_captured.call[:messages].first[:content]
    assert_equal 1, encoded.size
    assert_equal "data:image/jpeg;base64,ENC", encoded[0][:image_url][:url]
  end

  # Defensive guard: a canonicalized block should always be mappable, so an
  # unmappable type signals an internal-invariant violation (not user input,
  # which Rixie::Input rejects upstream).
  def test_chat_raises_on_unmappable_content_block
    adapter = build_adapter
    stub_client(adapter)
    content = [{"type" => "audio", "data" => "..."}]
    error = assert_raises(Rixie::InvalidContentError) do
      adapter.chat([user_msg(content)], tools: [])
    end
    assert_includes error.message, "Unmappable content block"
  end

  # Defensive guard for a malformed image source (e.g. a corrupt/old store entry
  # replayed without re-normalization). Must raise rather than dereference a
  # non-Hash source and silently emit a degenerate `data:;base64,` URI.
  def test_chat_raises_on_image_block_with_non_hash_source
    adapter = build_adapter
    stub_client(adapter)
    [nil, "data:image/png;base64,AAA"].each do |bad_source|
      error = assert_raises(Rixie::InvalidContentError) do
        adapter.chat([user_msg([{"type" => "image", "source" => bad_source}])], tools: [])
      end
      assert_includes error.message, "Unmappable image source"
    end
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

  def test_chat_emits_response_format_when_schema_given
    adapter = build_adapter
    get_captured = stub_client(adapter)
    schema = {"type" => "object", "properties" => {"x" => {"type" => "string"}}, "required" => ["x"]}
    adapter.chat([], tools: [], schema: schema)
    rf = get_captured.call[:response_format]
    assert_equal "json_schema", rf[:type]
    assert_equal "structured_output", rf[:json_schema][:name]
    assert_equal schema, rf[:json_schema][:schema]
  end

  def test_chat_omits_response_format_when_no_schema
    adapter = build_adapter
    get_captured = stub_client(adapter)
    adapter.chat([], tools: [])
    refute get_captured.call.key?(:response_format)
  end

  def test_chat_merges_provider_params_into_request
    adapter = build_adapter(provider_params: {max_completion_tokens: 500, seed: 42})
    get_captured = stub_client(adapter)
    adapter.chat([], tools: [])
    assert_equal 500, get_captured.call[:max_completion_tokens]
    assert_equal 42, get_captured.call[:seed]
  end

  def test_chat_does_not_include_provider_params_when_nil
    adapter = build_adapter
    get_captured = stub_client(adapter)
    adapter.chat([], tools: [])
    refute get_captured.call.key?(:max_completion_tokens)
  end

  def test_provider_params_take_precedence_over_standard_params
    adapter = build_adapter(temperature: 0.3, provider_params: {temperature: 0.9})
    get_captured = stub_client(adapter)
    adapter.chat([], tools: [])
    assert_equal 0.9, get_captured.call[:temperature]
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

  def assistant_msg_with_tool_call
    tool_call = Rixie::LLM::ToolCall.new(id: "c1", name: "get_weather", arguments: {"city" => "Tokyo"})
    Rixie::Message::Assistant.new(content: nil, tool_calls: [tool_call])
  end

  # Per the OpenAI spec, an assistant message with tool_calls legitimately carries
  # content: null. Default behavior must be unchanged for plain OpenAI/Ollama.
  def test_chat_sends_null_content_unchanged_by_default
    adapter = build_adapter
    get_captured = stub_client(adapter)
    adapter.chat([assistant_msg_with_tool_call], tools: [])
    msg = get_captured.call[:messages].first
    assert_nil msg[:content]
    assert_equal 1, msg[:tool_calls].size
  end

  # Opt-in for strict OpenAI-compatible backends (e.g. Cloudflare Workers AI)
  # that reject content: null alongside tool_calls.
  def test_chat_replaces_null_content_with_empty_string_when_fallback_enabled
    adapter = build_adapter(null_content_fallback: true)
    get_captured = stub_client(adapter)
    adapter.chat([assistant_msg_with_tool_call], tools: [])
    msg = get_captured.call[:messages].first
    assert_equal "", msg[:content]
    assert_equal 1, msg[:tool_calls].size
  end

  def test_chat_does_not_replace_non_null_assistant_content_when_fallback_enabled
    adapter = build_adapter(null_content_fallback: true)
    get_captured = stub_client(adapter)
    msg = Rixie::Message::Assistant.new(content: "Hello", tool_calls: [])
    adapter.chat([msg], tools: [])
    assert_equal "Hello", get_captured.call[:messages].first[:content]
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
