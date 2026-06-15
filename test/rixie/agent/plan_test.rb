# frozen_string_literal: true

require "test_helper"

class PlanTest < Minitest::Test
  def finish_response(content: "Done.")
    {"choices" => [{"message" => {"content" => content, "tool_calls" => nil}}]}
  end

  def plan_response(steps:)
    finish_response(content: JSON.generate({"steps" => steps}))
  end

  def make_agent(responses = [])
    adapter = Rixie::LLM::Adapter::Dummy.new(responses)
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    Rixie::Agent.new(instructions: "You are an assistant.", llm_client: client)
  end

  def test_instructions_appends_planning_prompt_to_base_agent_instructions
    plan = Rixie::Agent::Plan.new(base_agent: make_agent)
    assert_includes plan.instructions, "You are an assistant."
    assert_includes plan.instructions, "ordered list of concrete steps"
    assert_includes plan.instructions, "\"steps\" array"
  end

  def test_tools_is_empty
    base_tool = Rixie::Tool.new(name: "search", description: "s", input_schema: {}, call: ->(_) {})
    agent = Rixie::Agent.new(
      instructions: "...",
      tools: [base_tool],
      llm_client: Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: Rixie::LLM::Adapter::Dummy.new([]))
    )
    plan = Rixie::Agent::Plan.new(base_agent: agent)

    # Planning exposes no tools — it produces the plan as structured output.
    assert_empty plan.tools
  end

  def test_instructions_list_base_agent_tools_for_planning
    base_tool = Rixie::Tool.new(name: "current_time", description: "Returns the current time.", input_schema: {}, call: ->(_) {})
    agent = Rixie::Agent.new(
      instructions: "...",
      tools: [base_tool],
      llm_client: Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: Rixie::LLM::Adapter::Dummy.new([]))
    )
    plan = Rixie::Agent::Plan.new(base_agent: agent)

    assert_includes plan.instructions, "- current_time: Returns the current time."
  end

  def test_plan_schema_requires_a_steps_array
    schema = Rixie::Agent::Plan::PLAN_SCHEMA
    assert_equal "object", schema["type"]
    assert_equal ["steps"], schema["required"]
    assert_equal "array", schema.dig("properties", "steps", "type")
  end

  def test_think_returns_the_plan_as_a_parsed_hash
    steps = [{"title" => "Step 1", "description" => "Do step 1"}]
    plan = Rixie::Agent::Plan.new(base_agent: make_agent([plan_response(steps: steps)]))
    result = plan.think(messages: [], listener: Rixie::EventListener.new)

    assert_instance_of Rixie::Agent::ThinkResult, result
    assert_equal({"steps" => steps}, result.content)
  end

  def test_internal_agent_inherits_base_agent_settings
    counter = ->(messages) { messages.size }
    adapter = Rixie::LLM::Adapter::Dummy.new([])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    agent = Rixie::Agent.new(
      instructions: "...", llm_client: client,
      max_steps: 3, token_counter: counter
    )
    internal = Rixie::Agent::Plan.new(base_agent: agent).send(:internal_agent)

    assert_equal 3, internal.max_steps
    assert_same counter, internal.token_counter
  end
end
