# frozen_string_literal: true

require "securerandom"

module Rixie
  class Session
    attr_reader :agent, :tasks, :session_id, :stream_client

    def initialize(agent: nil, stream_client: nil, instructions: nil, tools: [], model: nil, provider: nil, max_steps: nil, llm_client: nil, store: nil, initial_context: [], request_timeout: nil, max_tokens: nil, temperature: nil, token_counter: nil)
      resolved_provider = provider || Rixie.config.default_provider
      resolved_model = model || Rixie.config.default_model
      resolved_timeout = request_timeout || Rixie.config.request_timeout

      resolved_max_tokens = max_tokens || Rixie.config.default_max_tokens
      resolved_temperature = temperature || Rixie.config.default_temperature

      @agent = agent || Agent.new(
        instructions: instructions,
        tools: tools,
        max_steps: max_steps || Rixie.config.default_max_steps,
        llm_client: llm_client || LLM::Client.new(
          model: resolved_model,
          provider: resolved_provider,
          request_timeout: resolved_timeout,
          max_tokens: resolved_max_tokens,
          temperature: resolved_temperature
        )
      )

      @stream_client = if agent.nil?
        stream_client || (resolved_provider ? LLM::Client.new(
          model: resolved_model,
          provider: resolved_provider,
          stream: true,
          request_timeout: resolved_timeout,
          max_tokens: resolved_max_tokens,
          temperature: resolved_temperature
        ) : nil)
      else
        stream_client
      end

      @store = store || Rixie.config.store || Store::Memory.new
      @token_counter = token_counter || TokenCounter::DEFAULT
      @initial_context = initial_context
      @session_id = SecureRandom.uuid
      @tasks = []
      @summary = nil
    end

    def chat(user_input, strategy: Strategy::Simple.new)
      task = Task.new(user_input: user_input, agent: agent, context: context, strategy: strategy)
      task.execute
      @tasks << task
      @store.save(@session_id, context)
      task.output
    end

    def live(user_input, strategy: Strategy::Simple.new)
      Enumerator.new do |yielder|
        stream_agent = @agent.with_llm_client(@stream_client)

        listener = EventListener.new
        listener.on(Event::Token) { |e| yielder << e }
        listener.on(Event::StepCompleted) { |e| yielder << e }
        listener.on(Event::Finished) { |e| yielder << e }

        task = Task.new(
          user_input: user_input,
          agent: stream_agent,
          context: context,
          strategy: strategy
        )
        task.execute(listener:)
        @tasks << task
        @store.save(@session_id, context)
      end
    end

    def compress!(keep_recent: 0, compressor: nil)
      return if context.empty?

      recent = context.last(keep_recent)
      to_compress = context.first(context.size - recent.size)

      return if to_compress.empty?

      summary_input = to_compress.flat_map(&:to_message).to_json

      Rixie.logger.info { "[Session] compressing #{to_compress.size} context entries (keep_recent: #{keep_recent})" }
      task = Task.new(
        user_input: summary_input,
        agent: compressor || Agent::Compressor.new(base_agent: @agent),
        context: [],
        strategy: Strategy::Simple.new,
        silent: true
      )
      task.execute

      @summary = Context::Summary.new(content: task.output)
      @tasks = []
      @initial_context = recent
      @store.save(@session_id, context)
    end

    def context_size
      @token_counter.call(context.flat_map(&:to_message))
    end

    def context
      base = @summary ? [@summary] : []
      base + @initial_context + @tasks.select(&:completed?).flat_map(&:to_history)
    end
  end
end
