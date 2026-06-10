# frozen_string_literal: true

require "securerandom"

module Rixie
  class Session
    attr_reader :agent, :tasks, :session_id, :stream_client

    def initialize(agent: nil, stream_client: nil, instructions: nil, tools: [], model: nil, provider: nil, max_steps: nil, llm_client: nil, store: nil, initial_context: [], request_timeout: nil, temperature: nil, token_counter: nil, parallel_tool_calls: false, subscribers: [], provider_params: nil)
      resolved_provider = provider || Rixie.config.default_provider
      resolved_model = model || Rixie.config.default_model
      resolved_timeout = request_timeout || Rixie.config.request_timeout

      resolved_temperature = temperature || Rixie.config.default_temperature
      resolved_provider_params = provider_params || Rixie.config.default_provider_params

      @token_counter = token_counter || TokenCounter::DEFAULT
      @agent = agent || Agent.new(
        instructions: instructions,
        tools: tools,
        max_steps: max_steps || Rixie.config.default_max_steps,
        parallel_tool_calls: parallel_tool_calls,
        token_counter: @token_counter,
        llm_client: llm_client || LLM::Client.new(
          model: resolved_model,
          provider: resolved_provider,
          request_timeout: resolved_timeout,
          temperature: resolved_temperature,
          parallel_tool_calls: parallel_tool_calls,
          provider_params: resolved_provider_params
        )
      )

      @stream_client = if agent.nil?
        stream_client || (resolved_provider ? LLM::Client.new(
          model: resolved_model,
          provider: resolved_provider,
          stream: true,
          request_timeout: resolved_timeout,
          temperature: resolved_temperature,
          parallel_tool_calls: parallel_tool_calls,
          provider_params: resolved_provider_params
        ) : nil)
      else
        stream_client
      end

      default_subs = Rixie.config.default_subscribers || [default_log_subscriber]
      @subscribers = default_subs + subscribers
      @store = store || Rixie.config.store || Store::Memory.new
      @initial_context = initial_context
      @session_id = SecureRandom.uuid
      @tasks = []
      @summary = nil
    end

    def chat(user_input, strategy: Strategy::Simple.new)
      task = Task.new(user_input: user_input, agent: agent, context: context, strategy: strategy, subscribers: @subscribers, session_id: @session_id)
      task.execute
      @tasks << task
      @store.save(@session_id, context)
      task.output
    end

    def live(user_input, strategy: Strategy::Simple.new)
      Enumerator.new do |yielder|
        stream_agent = @agent.with_llm_client(@stream_client)
        stream_sub = build_stream_subscriber(yielder)

        task = Task.new(
          user_input: user_input,
          agent: stream_agent,
          context: context,
          strategy: strategy,
          subscribers: @subscribers + [stream_sub],
          session_id: @session_id
        )
        task.execute
        @tasks << task
        @store.save(@session_id, context)
      end
    end

    def compress!(keep_recent: 0, compressor: nil)
      return if context.empty?

      recent = context.last(keep_recent)
      to_compress = context.first(context.size - recent.size)

      return if to_compress.empty?

      summary_input = to_compress.flat_map(&:to_message).map { |msg|
        case msg
        when Message::System then "[system] #{msg.content}"
        when Message::User then "[user] #{msg.content}"
        when Message::Assistant then "[assistant] #{msg.content}"
        when Message::Tool then "[tool_result id=#{msg.tool_call_id}] #{msg.content}"
        end
      }.join("\n\n")

      listener = EventListener.new(session_id: @session_id)
      @subscribers.each { |s| s.subscribe(listener) }
      listener.emit(Event::CompressionStart.new(entry_count: to_compress.size, keep_recent: keep_recent))

      task = Task.new(
        user_input: summary_input,
        agent: compressor || Agent::Compressor.new(base_agent: @agent),
        context: [],
        strategy: Strategy::Simple.new
      )
      task.execute

      @summary = Context::Summary.new(content: task.output)
      @tasks = []
      @initial_context = recent
      @store.save(@session_id, context)
      listener.emit(Event::CompressionEnd.new(status: "completed", entry_count: context.size))
    rescue
      listener&.emit(Event::CompressionEnd.new(status: "failed", entry_count: nil))
      raise
    end

    def context_size
      @token_counter.call(context.flat_map(&:to_message))
    end

    def context
      base = @summary ? [@summary] : []
      base + @initial_context + @tasks.select(&:completed?).flat_map(&:to_history)
    end

    private

    def default_log_subscriber
      case Rixie.config.log_format
      when :json then Rixie::Subscribers::JsonLogger.new(logger: Rixie.config.logger)
      else Rixie::Subscribers::Logger.new(logger: Rixie.config.logger)
      end
    end

    def build_stream_subscriber(yielder)
      sub = Object.new
      sub.define_singleton_method(:subscribe) do |listener|
        listener.on(Event::Token) { |envelope| yielder << envelope }
        listener.on(Event::ThoughtCompleted) { |envelope| yielder << envelope }
        listener.on(Event::Finished) { |envelope| yielder << envelope }
        listener.on(Event::ToolCallStart) { |envelope| yielder << envelope }
        listener.on(Event::ToolCallEnd) { |envelope| yielder << envelope }
        listener.on(Event::ToolCallsCompleted) { |envelope| yielder << envelope }
      end
      sub
    end
  end
end
