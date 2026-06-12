# frozen_string_literal: true

require "test_helper"

class ReActAgentTest < Minitest::Test
  def finish_response(content: "Final answer.")
    {"choices" => [{"message" => {"content" => content, "tool_calls" => nil}}]}
  end

  def tool_call_response(id: "tc_1", name: "search", arguments: {"query" => "rixie"}, content: nil)
    {
      "choices" => [{
        "message" => {
          "content" => content,
          "tool_calls" => [{
            "id" => id,
            "function" => {"name" => name, "arguments" => JSON.dump(arguments)}
          }]
        }
      }]
    }
  end

  def make_agent(responses = [], tools: [], instructions: "You are an assistant.")
    adapter = Rixie::LLM::Adapter::Dummy.new(responses)
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    Rixie::Agent.new(instructions: instructions, tools: tools, llm_client: client)
  end

  def test_instructions_appends_react_prompt_to_base_agent_instructions
    react = Rixie::Agent::ReAct.new(base_agent: make_agent)
    assert_includes react.instructions, "You are an assistant."
    assert_includes react.instructions, "ReAct"
    assert_includes react.instructions, "Thought:"
  end

  def test_instructions_handles_nil_base_instructions
    agent = make_agent(instructions: nil)
    react = Rixie::Agent::ReAct.new(base_agent: agent)
    refute_nil react.instructions
    assert_includes react.instructions, "ReAct"
    refute react.instructions.start_with?("\n\n")
  end

  def test_instructions_handles_empty_base_instructions
    agent = make_agent(instructions: "")
    react = Rixie::Agent::ReAct.new(base_agent: agent)
    refute react.instructions.start_with?("\n\n")
  end

  def test_tools_pass_through_base_agent_tools_unchanged
    base_tool = Rixie::Tool.new(name: "search", description: "s", input_schema: {}, call: ->(_) {})
    agent = make_agent(tools: [base_tool])
    react = Rixie::Agent::ReAct.new(base_agent: agent)
    assert_equal [base_tool], react.tools
  end

  def test_llm_client_returns_base_agent_llm_client
    agent = make_agent
    react = Rixie::Agent::ReAct.new(base_agent: agent)
    assert_same agent.llm_client, react.llm_client
  end

  def test_think_returns_think_result_on_finish
    agent = make_agent([finish_response(content: "Done.")])
    react = Rixie::Agent::ReAct.new(base_agent: agent)
    listener = Rixie::EventListener.new
    result = react.think(messages: [], listener: listener)
    assert_instance_of Rixie::Agent::ThinkResult, result
    assert_equal "Done.", result.content
    assert_equal 1, result.thoughts.size
    assert result.thoughts.first.finish?
  end

  def test_think_iterates_tool_call_then_finish
    base_tool = Rixie::Tool.new(name: "search", description: "s", input_schema: {}, call: ->(_) { "result" })
    agent = make_agent(
      [tool_call_response(content: "Thought: I need to search for rixie."), finish_response(content: "Found it.")],
      tools: [base_tool]
    )
    react = Rixie::Agent::ReAct.new(base_agent: agent)
    listener = Rixie::EventListener.new
    result = react.think(messages: [], listener: listener)
    assert_equal "Found it.", result.content
    assert_equal 2, result.thoughts.size
    assert result.thoughts[0].tool_call?
    assert result.thoughts[1].finish?
  end

  def test_internal_agent_inherits_max_steps_and_token_counter_from_base_agent
    counter = ->(messages) { messages.size }
    adapter = Rixie::LLM::Adapter::Dummy.new([])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    agent = Rixie::Agent.new(instructions: "...", llm_client: client, max_steps: 3, token_counter: counter)
    internal = Rixie::Agent::ReAct.new(base_agent: agent).send(:internal_agent)

    assert_equal 3, internal.max_steps
    assert_same counter, internal.token_counter
  end

  def test_think_respects_base_agent_max_steps
    base_tool = Rixie::Tool.new(name: "search", description: "s", input_schema: {}, call: ->(_) { "result" })
    adapter = Rixie::LLM::Adapter::Dummy.new([tool_call_response, tool_call_response])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    agent = Rixie::Agent.new(instructions: "...", tools: [base_tool], llm_client: client, max_steps: 1)
    react = Rixie::Agent::ReAct.new(base_agent: agent)

    assert_raises(Rixie::MaxStepsExceededError) do
      react.think(messages: [], listener: Rixie::EventListener.new)
    end
  end

  def test_internal_agent_uses_parallel_tool_calls_false
    react = Rixie::Agent::ReAct.new(base_agent: make_agent)
    internal = react.send(:internal_agent)
    refute internal.parallel_tool_calls
  end

  def test_internal_agent_forces_parallel_tool_calls_false_even_if_base_agent_has_true
    adapter = Rixie::LLM::Adapter::Dummy.new([])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    agent = Rixie::Agent.new(instructions: "...", llm_client: client, parallel_tool_calls: true)
    react = Rixie::Agent::ReAct.new(base_agent: agent)
    refute react.send(:internal_agent).parallel_tool_calls
  end

  def test_custom_react_instructions_are_used
    custom = "Custom ReAct guidance."
    react = Rixie::Agent::ReAct.new(base_agent: make_agent, react_instructions: custom)
    assert_includes react.instructions, custom
    refute_includes react.instructions, "Thought:"
  end
end
