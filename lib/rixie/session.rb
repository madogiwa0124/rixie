# frozen_string_literal: true

require "securerandom"

module Rixie
  class Session
    attr_reader :agent, :tasks, :session_id

    def initialize(agent: nil, instructions: nil, tools: [], model: nil, provider: nil, max_steps: nil, llm_client: nil, store: nil, initial_context: [], request_timeout: nil, max_tokens: nil, temperature: nil, token_counter: nil)
      @agent = agent || Agent.new(
        instructions: instructions,
        tools: tools,
        max_steps: max_steps || Rixie.config.default_max_steps,
        llm_client: llm_client || LLM::Client.new(
          model: model || Rixie.config.default_model,
          provider: provider || Rixie.config.default_provider,
          request_timeout: request_timeout || Rixie.config.request_timeout,
          max_tokens: max_tokens || Rixie.config.default_max_tokens,
          temperature: temperature || Rixie.config.default_temperature
        )
      )
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

    def compress!(keep_recent: 0)
      return if context.empty?

      recent = context.last(keep_recent)
      to_compress = context.first(context.size - recent.size)

      return if to_compress.empty?

      summary_input = to_compress.flat_map(&:to_message).to_json

      Rixie.logger.info { "[Session] compressing #{to_compress.size} context entries (keep_recent: #{keep_recent})" }
      task = Task.new(
        user_input: summary_input,
        agent: Agent::Compressor.new(base_agent: @agent),
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
