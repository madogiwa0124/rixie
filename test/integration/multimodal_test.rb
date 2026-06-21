# frozen_string_literal: true

require_relative "test_helper"
require "base64"

# Scenario: multimodal (image) input via Session#chat.
#
# Verifies that an Array of Rixie content blocks (text + base64 image) flows
# end-to-end through Session → Task → Run → PromptBuilder → the LLM adapter,
# is recorded in conversation history, and is replayed on later turns. The
# adapter-level wire-format translation is covered by the OpenAI adapter unit
# tests; here we assert the integration concern — that the multimodal input
# survives the pipeline unchanged and accumulates in context.
#
# In live mode the request hits a real (vision-capable) provider, so we use a
# small but real PNG fixture (320x240, a green square / red circle / yellow
# triangle on a light-blue background) rather than a degenerate 1x1 pixel, which
# some vision preprocessors reject.
class MultimodalTest < Integration::TestCase
  IMAGE_DATA = Base64.strict_encode64(File.binread(File.expand_path("../fixtures/sample.png", __dir__)))

  # Records every batch of messages handed to the adapter, so a test can assert
  # the multimodal content reaches the LLM layer. Dummy-only by construction.
  class CapturingAdapter
    attr_reader :calls

    def initialize(response)
      @response = response
      @calls = []
    end

    def chat(messages, tools:, schema: nil)
      @calls << messages
      Rixie::LLM::Response.from_openai_wire(@response)
    end

    def stream(messages, tools:, schema: nil, &)
      chat(messages, tools: tools)
    end
  end

  def image_content(text: "What's in this image?")
    blocks = []
    blocks << {type: "text", text: text} unless text.nil?
    blocks << {type: "image", source: {type: "base64", media_type: "image/png", data: IMAGE_DATA}}
    blocks
  end

  def test_chat_accepts_text_and_image_content
    client = build_client(responses: [finish_response(content: "A red pixel.")])
    session = Rixie::Session.new(instructions: "Describe the image.", llm_client: client)

    output = session.chat(image_content)

    assert session.tasks.first.completed?
    assert_instance_of String, output
    refute_empty output
    assert_equal "A red pixel.", output unless live?
  end

  def test_image_only_content_works
    client = build_client(responses: [finish_response(content: "ok")])
    session = Rixie::Session.new(instructions: "Describe it.", llm_client: client)

    output = session.chat(image_content(text: nil))

    assert session.tasks.first.completed?
    assert_instance_of String, output
    refute_empty output
  end

  def test_image_content_reaches_the_llm_messages
    adapter = CapturingAdapter.new(finish_response(content: "ok"))
    session = Rixie::Session.new(instructions: "sys", llm_client: Rixie::LLM::Client.new(adapter: adapter))

    content = image_content
    session.chat(content)

    # Session#chat normalizes input to canonical (string-keyed) content blocks.
    user_msg = adapter.calls.last.find { |m| m.is_a?(Rixie::Message::User) }
    assert_equal Rixie::Input.normalize(content), user_msg.content
  end

  def test_image_content_is_recorded_in_session_context
    client = build_client(responses: [finish_response(content: "ok")])
    session = Rixie::Session.new(instructions: "sys", llm_client: client)

    content = image_content
    session.chat(content)

    history = session.context.first
    assert_instance_of Rixie::Context::History, history
    user_msg = history.to_message.find { |m| m.is_a?(Rixie::Message::User) }
    assert_equal Rixie::Input.normalize(content), user_msg.content
  end

  def test_image_content_is_replayed_on_later_turns
    adapter = CapturingAdapter.new(finish_response(content: "ok"))
    session = Rixie::Session.new(instructions: "sys", llm_client: Rixie::LLM::Client.new(adapter: adapter))

    content = image_content
    session.chat(content)
    session.chat("And now?")

    # The second turn's prompt must still carry the first turn's image content
    # (in canonical, string-keyed form).
    replayed = adapter.calls.last.select { |m| m.is_a?(Rixie::Message::User) }.map(&:content)
    assert_includes replayed, Rixie::Input.normalize(content)
  end
end
