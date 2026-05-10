# frozen_string_literal: true

require "securerandom"

module Rixie
  class Session
    attr_reader :agent, :tasks, :session_id

    def initialize(agent: nil, instructions: nil, tools: [], model: nil, provider: nil, max_steps: nil, llm_client: nil, store: nil, initial_context: [], request_timeout: nil, max_tokens: nil, temperature: nil)
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
      @initial_context = initial_context
      @session_id = SecureRandom.uuid
      @tasks = []
    end

    def chat(user_input, strategy: Strategy::Simple.new)
      task = Task.new(user_input: user_input, agent: agent, context: context, strategy: strategy)
      task.execute
      @tasks << task
      @store.save(@session_id, context)
      task.output
    end

    def context
      @initial_context + @tasks.select(&:completed?).flat_map(&:to_history)
    end
  end
end
