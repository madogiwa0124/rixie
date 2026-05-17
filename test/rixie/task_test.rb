# frozen_string_literal: true

require "test_helper"

class TaskTest < Minitest::Test
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

  def make_agent(responses, tools: [])
    adapter = Rixie::LLM::Adapter::Dummy.new(responses)
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    Rixie::Agent.new(instructions: "Be helpful.", tools: tools, llm_client: client)
  end

  def make_task(agent, strategy: Rixie::Strategy::Simple.new, context: [])
    Rixie::Task.new(user_input: "Hello", agent: agent, context: context, strategy: strategy)
  end

  def test_execute_sets_status_to_completed_on_success
    task = make_task(make_agent([finish_response]))
    task.execute
    assert_equal "completed", task.status
  end

  def test_execute_sets_output_to_strategy_result
    task = make_task(make_agent([finish_response(content: "My answer")]))
    task.execute
    assert_equal "My answer", task.output
  end

  def test_execute_sets_status_to_failed_on_exception
    adapter = Rixie::LLM::Adapter::Dummy.new([])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    agent = Rixie::Agent.new(instructions: "s", llm_client: client)
    task = make_task(agent)
    assert_raises(RuntimeError) { task.execute }
    assert_equal "failed", task.status
  end

  def test_execute_reraises_exception_on_failure
    adapter = Rixie::LLM::Adapter::Dummy.new([])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    agent = Rixie::Agent.new(instructions: "s", llm_client: client)
    task = make_task(agent)
    assert_raises(RuntimeError) { task.execute }
  end

  def test_execute_populates_runs_last_thoughts_via_agent_think
    tool = Rixie::Tool.new(name: "search", description: "s", input_schema: {}, call: ->(_) { "found" })
    agent = make_agent(
      [tool_call_response(id: "c1", name: "search"), finish_response],
      tools: [tool]
    )
    task = make_task(agent)
    task.execute

    assert_equal 2, task.runs.last.thoughts.size
    assert_equal "search", task.runs.last.thoughts.first.tool_calls.first.name
  end

  def test_completed_returns_true_when_completed
    task = make_task(make_agent([finish_response]))
    task.execute
    assert task.completed?
  end

  def test_failed_returns_true_when_failed
    adapter = Rixie::LLM::Adapter::Dummy.new([])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    task = make_task(Rixie::Agent.new(instructions: "s", llm_client: client))
    assert_raises(RuntimeError) { task.execute }
    assert task.failed?
  end

  def test_to_history_returns_only_completed_runs_histories
    task = make_task(make_agent([finish_response(content: "Result")]))
    task.execute
    histories = task.to_history
    assert_equal 1, histories.size
    assert_instance_of Rixie::Context::History, histories.first
  end

  def test_to_history_excludes_failed_runs
    adapter = Rixie::LLM::Adapter::Dummy.new([finish_response(content: "ok")])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    agent = Rixie::Agent.new(instructions: "s", llm_client: client)
    good_run = Rixie::Run.new(user_input: "Hello", agent: agent, context: [])

    strategy = Object.new
    strategy.define_singleton_method(:run) do |task:, listener:|
      failed_run = Rixie::Run.new(user_input: task.user_input, agent: task.agent, context: task.context)
      task.runs << failed_run
      failed_run.instance_variable_set(:@status, "failed")
      task.runs << good_run
      good_run.execute(listener:)
      good_run.output
    end

    task = Rixie::Task.new(user_input: "Hello", agent: agent, context: [], strategy: strategy)
    task.execute

    histories = task.to_history
    assert_equal 1, histories.size
  end

  def test_execute_emits_task_start_before_strategy_runs
    order = []
    strategy = Object.new
    strategy.define_singleton_method(:run) do |task:, listener:|
      order << :strategy_ran
      "output"
    end

    sub = Class.new(Rixie::Subscriber) do
      def initialize(order) = (@order = order)

      def subscribe(listener)
        listener.on(Rixie::Event::TaskStart) { |_| @order << :task_start }
      end
    end.new(order)

    task = Rixie::Task.new(
      user_input: "Hello", agent: make_agent([]), context: [],
      strategy: strategy, subscribers: [sub]
    )
    task.execute

    assert_equal [:task_start, :strategy_ran], order
  end

  def test_execute_emits_task_end_with_completed_on_success
    received = []
    sub = Class.new(Rixie::Subscriber) do
      def initialize(received) = (@received = received)

      def subscribe(listener)
        listener.on(Rixie::Event::TaskEnd) { |envelope| @received << envelope }
      end
    end.new(received)

    task = Rixie::Task.new(
      user_input: "Hello", agent: make_agent([finish_response]),
      context: [], strategy: Rixie::Strategy::Simple.new,
      subscribers: [sub]
    )
    task.execute

    assert_equal 1, received.size
    assert_equal "completed", received.first.event.status
    assert_equal "Done!", received.first.event.output
  end

  def test_execute_emits_task_end_with_failed_on_failure
    received = []
    sub = Class.new(Rixie::Subscriber) do
      def initialize(received) = (@received = received)

      def subscribe(listener)
        listener.on(Rixie::Event::TaskEnd) { |envelope| @received << envelope }
      end
    end.new(received)

    adapter = Rixie::LLM::Adapter::Dummy.new([])
    client = Rixie::LLM::Client.new(model: "gpt-4o", provider: "openai", adapter: adapter)
    agent = Rixie::Agent.new(instructions: "s", llm_client: client)
    task = Rixie::Task.new(
      user_input: "Hello", agent: agent, context: [],
      strategy: Rixie::Strategy::Simple.new, subscribers: [sub]
    )

    assert_raises(RuntimeError) { task.execute }
    assert_equal 1, received.size
    assert_equal "failed", received.first.event.status
    assert_nil received.first.event.output
  end

  def test_subscribers_defaults_to_empty
    task = Rixie::Task.new(
      user_input: "Hello", agent: make_agent([finish_response]),
      context: [], strategy: Rixie::Strategy::Simple.new
    )
    task.execute
    assert task.completed?
  end

  def test_custom_subscriber_receives_events_during_execute
    received = []
    sub = Class.new(Rixie::Subscriber) do
      def initialize(received) = (@received = received)

      def subscribe(listener)
        listener.on(Rixie::Event::TaskStart) { |envelope| @received << envelope }
        listener.on(Rixie::Event::TaskEnd) { |envelope| @received << envelope }
      end
    end.new(received)

    task = Rixie::Task.new(
      user_input: "Hello", agent: make_agent([finish_response]),
      context: [], strategy: Rixie::Strategy::Simple.new,
      subscribers: [sub]
    )
    task.execute

    assert_equal 2, received.size
    assert_instance_of Rixie::Event::TaskStart, received[0].event
    assert_instance_of Rixie::Event::TaskEnd, received[1].event
  end
end
