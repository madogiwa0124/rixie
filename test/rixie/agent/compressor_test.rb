# frozen_string_literal: true

require "test_helper"

class CompressorTest < Minitest::Test
  def finish_response(content: "Summary of conversation.")
    {"choices" => [{"message" => {"content" => content, "tool_calls" => nil}}]}
  end

  def make_base_agent(responses = [])
    adapter = Rixie::LLM::Adapter::Dummy.new(responses)
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    Rixie::Agent.new(instructions: "You are an assistant.", llm_client: client)
  end

  def test_instructions_contains_summarization_prompt
    compressor = Rixie::Agent::Compressor.new(base_agent: make_base_agent)
    assert_includes compressor.instructions, "conversation summarizer"
    assert_includes compressor.instructions, "preserving key facts"
  end

  def test_default_instructions_equals_constant
    compressor = Rixie::Agent::Compressor.new(base_agent: make_base_agent)
    assert_equal Rixie::Agent::Compressor::DEFAULT_SUMMARIZATION_INSTRUCTIONS, compressor.instructions
  end

  def test_custom_summarization_instructions_overrides_default
    compressor = Rixie::Agent::Compressor.new(
      base_agent: make_base_agent,
      summarization_instructions: "Custom summary prompt."
    )
    assert_equal "Custom summary prompt.", compressor.instructions
  end

  def test_tools_returns_empty_array
    compressor = Rixie::Agent::Compressor.new(base_agent: make_base_agent)
    assert_equal [], compressor.tools
  end

  def test_think_delegates_to_base_agent
    base_agent = make_base_agent([finish_response(content: "Summary text")])
    compressor = Rixie::Agent::Compressor.new(base_agent: base_agent)
    listener = Rixie::EventListener.new
    finished_content = nil
    listener.on(Rixie::Event::Finished) { |e| finished_content = e.content }
    compressor.think(messages: [{role: "user", content: "history"}], listener: listener)
    assert_equal "Summary text", finished_content
  end
end
