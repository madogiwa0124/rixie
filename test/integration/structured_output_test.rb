# frozen_string_literal: true

require_relative "test_helper"

# Scenario: structured output via Session#chat(schema:).
# Verifies the schema is applied only to the final answer, that tool-calling
# flows still work, and that validation failures retry the finish generation
# only — end-to-end through Session / Task / Run / Agent.
class StructuredOutputTest < Integration::TestCase
  SCHEMA = {
    "type" => "object",
    "properties" => {
      "title" => {"type" => "string"},
      "tags" => {"type" => "array", "items" => {"type" => "string"}}
    },
    "required" => ["title"]
  }.freeze

  def test_chat_with_schema_returns_a_hash_conforming_to_the_schema
    client = build_client(responses: [finish_response(content: '{"title":"Ruby","tags":["lang"]}')])
    session = Rixie::Session.new(
      instructions: "Respond with JSON matching the schema. Keys: title (string), tags (array of strings).",
      llm_client: client
    )

    output = session.chat("Summarize the Ruby language.", schema: SCHEMA)

    assert_instance_of Hash, output
    assert_kind_of String, output["title"]
    refute_empty output["title"]
    assert_equal({"title" => "Ruby", "tags" => ["lang"]}, output) unless live?
  end

  def test_chat_without_schema_still_returns_a_string
    client = build_client(responses: [finish_response(content: "plain answer")])
    session = Rixie::Session.new(instructions: "Be helpful.", llm_client: client)

    output = session.chat("Hi")

    assert_instance_of String, output
  end

  def test_tool_call_flow_then_structured_answer
    skip "dummy-sequence specific" if live?

    tool = Rixie::Tool.new(
      name: "web_search",
      description: "Search the web.",
      input_schema: {type: "object", properties: {query: {type: "string"}}},
      call: ->(_) { "Ruby is a programming language." }
    )
    client = build_client(responses: [
      tool_call_response(id: "c1", name: "web_search", arguments: {"query" => "ruby"}),
      finish_response(content: '{"title":"Ruby","tags":["programming"]}')
    ])
    session = Rixie::Session.new(instructions: "Search then answer as JSON.", tools: [tool], llm_client: client)

    output = session.chat("What is Ruby?", schema: SCHEMA)

    assert_equal({"title" => "Ruby", "tags" => ["programming"]}, output)
  end

  def test_validation_failure_retries_finish_only
    skip "dummy-sequence specific" if live?

    client = build_client(responses: [
      finish_response(content: "Here is the answer in prose."),
      finish_response(content: '{"title":"Recovered"}')
    ])
    session = Rixie::Session.new(instructions: "Answer as JSON.", llm_client: client)

    output = session.chat("Summarize.", schema: SCHEMA)

    assert_equal({"title" => "Recovered"}, output)
  end

  def test_structured_output_is_persisted_in_context_as_json
    skip "dummy-sequence specific" if live?

    client = build_client(responses: [
      finish_response(content: '{"title":"First"}'),
      finish_response(content: "second turn")
    ])
    session = Rixie::Session.new(instructions: "Be helpful.", llm_client: client)

    session.chat("First", schema: SCHEMA)
    second = session.chat("Second")

    assert_equal "second turn", second
    assert_equal 2, session.context.size
  end
end
