# frozen_string_literal: true

require "test_helper"

class SessionTest < Minitest::Test
  def finish_response(content: "Done!")
    {"choices" => [{"message" => {"content" => content, "tool_calls" => nil}}]}
  end

  def tool_call_response(id:, name:, arguments: {})
    {
      "choices" => [{
        "message" => {
          "content" => nil,
          "tool_calls" => [{"id" => id, "function" => {"name" => name, "arguments" => arguments.to_json}}]
        }
      }]
    }
  end

  def make_client(responses)
    adapter = Rixie::LLM::Adapter::Dummy.new(responses)
    Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
  end

  def make_stream_client(responses)
    adapter = Rixie::LLM::Adapter::Dummy.new(responses)
    Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter, stream: true)
  end

  def make_session(responses, **opts)
    Rixie::Session.new(instructions: "Be helpful.", llm_client: make_client(responses), **opts)
  end

  def make_session_with_live(chat_responses, stream_responses, **opts)
    Rixie::Session.new(
      instructions: "Be helpful.",
      llm_client: make_client(chat_responses),
      stream_client: make_stream_client(stream_responses),
      **opts
    )
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

  # compress! tests

  def test_compress_replaces_context_with_summary
    session = make_session([finish_response(content: "Turn 1"), finish_response(content: "Summary")])
    session.chat("Hello")
    session.compress!
    assert_instance_of Rixie::Context::Summary, session.context.first
  end

  def test_compress_clears_tasks
    session = make_session([finish_response(content: "Turn 1"), finish_response(content: "Summary")])
    session.chat("Hello")
    session.compress!
    assert_equal [], session.tasks
  end

  def test_compress_with_keep_recent_preserves_last_entries
    session = make_session([
      finish_response(content: "Turn 1"),
      finish_response(content: "Turn 2"),
      finish_response(content: "Turn 3"),
      finish_response(content: "Summary")
    ])
    session.chat("First")
    session.chat("Second")
    session.chat("Third")
    session.compress!(keep_recent: 2)

    ctx = session.context
    recent = ctx.select { |e| e.is_a?(Rixie::Context::History) }
    assert_equal 2, recent.size
  end

  def test_compress_with_keep_recent_summarizes_only_older_entries
    session = make_session([
      finish_response(content: "Turn 1"),
      finish_response(content: "Turn 2"),
      finish_response(content: "Turn 3"),
      finish_response(content: "Summary of first turn")
    ])
    session.chat("First")
    session.chat("Second")
    session.chat("Third")
    session.compress!(keep_recent: 2)

    ctx = session.context
    summary = ctx.find { |e| e.is_a?(Rixie::Context::Summary) }
    assert_equal "Summary of first turn", summary.content
  end

  def test_compress_persists_updated_context_via_store
    store = Rixie::Store::Memory.new
    session = make_session([finish_response(content: "Turn 1"), finish_response(content: "Summary")], store: store)
    session.chat("Hello")
    session.compress!

    session_id = session.instance_variable_get(:@session_id)
    saved = store.load(session_id)
    assert_instance_of Rixie::Context::Summary, saved.first
  end

  def test_compress_accepts_custom_compressor
    custom_instructions = "Summarize in one word."
    session = make_session([finish_response(content: "Turn 1"), finish_response(content: "OneWord")])
    session.chat("Hello")
    compressor = Rixie::Agent::Compressor.new(
      base_agent: session.agent,
      summarization_instructions: custom_instructions
    )
    session.compress!(compressor: compressor)
    assert_equal "OneWord", session.context.first.content
  end

  def test_compress_returns_early_when_context_is_empty
    session = make_session([])
    result = session.compress!
    assert_nil result
    assert_equal [], session.context
  end

  def test_compress_returns_early_when_to_compress_is_empty
    session = make_session([finish_response(content: "Turn 1")])
    session.chat("Hello")
    # keep_recent >= context.size means nothing to compress
    result = session.compress!(keep_recent: 5)
    assert_nil result
    assert_equal 1, session.context.size
    assert_instance_of Rixie::Context::History, session.context.first
  end

  def test_context_size_returns_approximate_token_count
    session = make_session([finish_response(content: "Hello world")])
    session.chat("Hi")
    size = session.context_size
    assert_kind_of Integer, size
    assert size > 0
  end

  def test_context_size_returns_zero_when_context_is_empty
    session = make_session([])
    assert_equal 0, session.context_size
  end

  def test_context_starts_with_summary_after_compress
    session = make_session([finish_response(content: "Turn 1"), finish_response(content: "Summary")])
    session.chat("Hello")
    session.compress!
    assert_instance_of Rixie::Context::Summary, session.context.first
  end

  def test_context_has_summary_then_recent_after_compress_with_keep_recent
    session = make_session([
      finish_response(content: "Turn 1"),
      finish_response(content: "Turn 2"),
      finish_response(content: "Summary")
    ])
    session.chat("First")
    session.chat("Second")
    session.compress!(keep_recent: 1)

    ctx = session.context
    assert_instance_of Rixie::Context::Summary, ctx.first
    assert_instance_of Rixie::Context::History, ctx.last
  end

  # live tests

  def test_live_returns_an_enumerator
    session = make_session_with_live([], [finish_response(content: "Hello")])
    result = session.live("hi")
    assert_instance_of Enumerator, result
  end

  def test_live_yields_event_token_events
    session = make_session_with_live([], [finish_response(content: "Hello")])
    events = session.live("hi").to_a
    tokens = events.select { |e| e.is_a?(Rixie::Event::Token) }
    refute_empty tokens
    assert_equal "Hello", tokens.map(&:delta).join
  end

  def test_live_yields_event_step_completed_events
    tool = Rixie::Tool.new(name: "search", description: "desc", input_schema: {}, call: ->(_) { "found" })
    session = Rixie::Session.new(
      instructions: "Be helpful.",
      tools: [tool],
      llm_client: make_client([]),
      stream_client: make_stream_client([
        tool_call_response(id: "c1", name: "search"),
        finish_response(content: "Done")
      ])
    )
    events = session.live("hi").to_a
    step_events = events.select { |e| e.is_a?(Rixie::Event::StepCompleted) }
    assert_equal 1, step_events.size
    assert_equal "search", step_events.first.tool_calls.first.name
  end

  def test_live_yields_event_finished_event
    session = make_session_with_live([], [finish_response(content: "Final answer")])
    events = session.live("hi").to_a
    finished = events.select { |e| e.is_a?(Rixie::Event::Finished) }
    assert_equal 1, finished.size
    assert_equal "Final answer", finished.first.content
  end

  def test_live_appends_task_to_tasks_after_enumeration
    session = make_session_with_live([], [finish_response])
    enum = session.live("hi")
    assert_equal 0, session.tasks.size
    enum.to_a
    assert_equal 1, session.tasks.size
    assert session.tasks.first.completed?
  end

  def test_live_persists_context_via_store_after_enumeration
    store = Rixie::Store::Memory.new
    session = make_session_with_live([], [finish_response(content: "Stored")], store: store)
    session.live("hi").to_a

    session_id = session.instance_variable_get(:@session_id)
    saved = store.load(session_id)
    assert_equal 1, saved.size
    assert_instance_of Rixie::Context::History, saved.first
  end

  def test_live_accepts_strategy_argument
    session = make_session_with_live([], [finish_response])
    result = session.live("hi", strategy: Rixie::Strategy::Simple.new).to_a
    refute_empty result
  end

  def test_live_uses_stream_client_internally
    stream_adapter = Rixie::LLM::Adapter::Dummy.new([finish_response(content: "from stream")])
    stream_client = Rixie::LLM::Client.new(
      model: "gpt-4o", provider: "openai",
      adapter: stream_adapter, stream: true
    )
    session = Rixie::Session.new(
      instructions: "Be helpful.",
      llm_client: make_client([]),
      stream_client: stream_client
    )
    events = session.live("hello").to_a
    finished = events.find { |e| e.is_a?(Rixie::Event::Finished) }
    assert_equal "from stream", finished.content
  end

  def test_live_does_not_execute_before_enumeration
    session = make_session_with_live([], [finish_response])
    enum = session.live("hi")
    # Task hasn't run yet
    assert_equal 0, session.tasks.size
    enum.to_a
    assert_equal 1, session.tasks.size
  end
end
