# frozen_string_literal: true

require "test_helper"

class SessionTest < Minitest::Test
  def finish_response(content: "Done!")
    raw = {"choices" => [{"message" => {"content" => content, "tool_calls" => nil}}]}
    Rixie::LLM::Response.new(raw: raw, provider: :openai)
  end

  def make_client(responses)
    adapter = DummyAdapter.new(responses)
    Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
  end

  def make_session(responses, **opts)
    Rixie::Session.new(instructions: "Be helpful.", llm_client: make_client(responses), **opts)
  end

  def test_chat_creates_and_executes_task
    session = make_session([finish_response])
    session.chat("Hello")
    assert_equal 1, session.tasks.size
    assert session.tasks.first.completed?
  end

  def test_chat_returns_task_output
    session = make_session([finish_response(content: "Hi there")])
    assert_equal "Hi there", session.chat("Hello")
  end

  def test_chat_appends_task_to_tasks
    session = make_session([finish_response, finish_response])
    session.chat("First")
    session.chat("Second")
    assert_equal 2, session.tasks.size
  end

  def test_context_returns_empty_array_initially
    session = make_session([])
    assert_equal [], session.context
  end

  def test_context_accumulates_completed_task_histories_across_multiple_chats
    session = make_session([finish_response(content: "Turn 1"), finish_response(content: "Turn 2")])
    session.chat("Message 1")
    session.chat("Message 2")

    histories = session.context
    assert_equal 2, histories.size
    assert_instance_of Rixie::Context::History, histories.first
  end

  def test_context_excludes_failed_tasks
    agent = Rixie::Agent.new(instructions: "Be helpful.", llm_client: make_client([finish_response(content: "Good")]))
    session = Rixie::Session.new(agent: agent)

    failing_task = Rixie::Task.new(
      user_input: "fail",
      agent: agent,
      context: [],
      strategy: Rixie::Strategy::Simple.new
    )
    failing_task.instance_variable_set(:@status, "failed")
    session.tasks << failing_task

    session.chat("Good request")

    assert_equal 1, session.context.size
  end

  def test_chat_persists_context_via_store
    store = Rixie::Store::Memory.new
    session = make_session([finish_response(content: "Stored")], store: store)
    session.chat("Hello")

    session_id = session.instance_variable_get(:@session_id)
    saved = store.load(session_id)
    assert_equal 1, saved.size
    assert_instance_of Rixie::Context::History, saved.first
  end

  def test_store_defaults_to_memory_when_config_store_is_nil
    Rixie.configure { |c| c.store = nil }
    session = make_session([finish_response])
    assert_instance_of Rixie::Store::Memory, session.instance_variable_get(:@store)
  end

  def test_strategy_defaults_to_strategy_simple
    session = make_session([finish_response])
    refute_nil session.chat("Hello")
  end

  def test_session_new_with_agent_uses_provided_agent
    agent = Rixie::Agent.new(instructions: "Custom.", llm_client: make_client([finish_response(content: "OK")]))
    session = Rixie::Session.new(agent: agent)
    assert_same agent, session.agent
    assert_equal "OK", session.chat("Hello")
  end

  def test_session_creates_agent_from_instructions
    session = make_session([finish_response])
    assert_instance_of Rixie::Agent, session.agent
    assert_equal "Be helpful.", session.agent.instructions
  end

  def test_max_steps_passed_to_agent
    session = Rixie::Session.new(instructions: "Hi.", max_steps: 3, llm_client: make_client([]))
    assert_equal 3, session.agent.instance_variable_get(:@max_steps)
  end

  def test_max_steps_falls_back_to_config
    Rixie.configure { |c| c.default_max_steps = 7 }
    session = Rixie::Session.new(instructions: "Hi.", llm_client: make_client([]))
    assert_equal 7, session.agent.instance_variable_get(:@max_steps)
  ensure
    Rixie.reset!
  end

  def test_provider_and_model_fall_back_to_config
    Rixie.configure do |c|
      c.default_provider = "openai"
      c.default_model = "gpt-4o"
    end
    # Resolver raises NoProviderError if provider is nil — so if Session
    # didn't resolve from config, Session.new would raise here.
    assert_instance_of Rixie::Session, Rixie::Session.new(instructions: "Hi.")
  ensure
    Rixie.reset!
  end
end
