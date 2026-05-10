# frozen_string_literal: true

require "test_helper"

class PlanTest < Minitest::Test
  def plan_done_response
    raw = {
      "choices" => [{
        "message" => {
          "content" => nil,
          "tool_calls" => [{
            "id" => "tc_1",
            "function" => {
              "name" => "plan_done",
              "arguments" => '{"steps":[{"title":"Step 1","description":"Do step 1"}]}'
            }
          }]
        }
      }]
    }
    Rixie::LLM::Response.new(raw: raw, provider: :openai)
  end

  def finish_response(content: "Done.")
    raw = {"choices" => [{"message" => {"content" => content, "tool_calls" => nil}}]}
    Rixie::LLM::Response.new(raw: raw, provider: :openai)
  end

  def make_agent(responses = [])
    adapter = DummyAdapter.new(responses)
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    Rixie::Agent.new(instructions: "You are an assistant.", llm_client: client)
  end

  def test_instructions_appends_planning_prompt_to_base_agent_instructions
    plan = Rixie::Agent::Plan.new(base_agent: make_agent)
    assert_includes plan.instructions, "You are an assistant."
    assert_includes plan.instructions, "First, make a plan to accomplish the given task."
    assert_includes plan.instructions, "call plan_done"
  end

  def test_tools_includes_base_agent_tools_plus_plan_done_tool
    base_tool = Rixie::Tool.new(name: "search", description: "s", input_schema: {}, call: ->(_) {})
    agent = Rixie::Agent.new(
      instructions: "...",
      tools: [base_tool],
      llm_client: Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: DummyAdapter.new([]))
    )
    plan = Rixie::Agent::Plan.new(base_agent: agent)

    assert_equal 2, plan.tools.size
    assert_equal "search", plan.tools.first.name
    assert_equal "plan_done", plan.tools.last.name
  end

  def test_think_executes_plan_done_tool_and_returns_finish_content
    agent = make_agent([plan_done_response, finish_response(content: "Plan complete.")])
    plan = Rixie::Agent::Plan.new(base_agent: agent)
    listener = Rixie::EventListener.new
    result = plan.think(messages: [], listener: listener)
    assert_equal "Plan complete.", result
  end

  def test_think_emits_step_completed_for_plan_done_tool_call
    agent = make_agent([plan_done_response, finish_response])
    plan = Rixie::Agent::Plan.new(base_agent: agent)
    listener = Rixie::EventListener.new
    received = []
    listener.on(:step_completed) { |p| received << p }
    plan.think(messages: [], listener: listener)
    assert_equal 1, received.size
    assert_equal "plan_done", received.first[:tool_calls].first.name
  end

  def test_plan_done_tool_name_is_plan_done
    assert_equal "plan_done", Rixie::Agent::Plan::PLAN_DONE_TOOL.name
  end

  def test_plan_done_tool_call_returns_arguments_as_is
    args = {"steps" => [{"title" => "Step 1", "description" => "Do it"}]}
    result = Rixie::Agent::Plan::PLAN_DONE_TOOL.call(args)
    assert_equal args, result
  end
end
