# frozen_string_literal: true

require_relative "rixie/version"
require_relative "rixie/error"
require_relative "rixie/configuration"
require_relative "rixie/event_listener"
require_relative "rixie/agent/tool_call"
require_relative "rixie/llm/response"
require_relative "rixie/llm/client"
require_relative "rixie/llm/adapter/dummy"
require_relative "rixie/tool"
require_relative "rixie/tool_executor"
require_relative "rixie/prompt_builder"
require_relative "rixie/context/history"
require_relative "rixie/context/plan"
require_relative "rixie/agent"
require_relative "rixie/agent/plan"
require_relative "rixie/store/base"
require_relative "rixie/store/memory"
require_relative "rixie/store/null"
require_relative "rixie/run"
require_relative "rixie/strategy/simple"
require_relative "rixie/strategy/plan_execute"
require_relative "rixie/task"
require_relative "rixie/session"

module Rixie
  module LLM
    module Adapter; end
  end

  class << self
    def configure
      yield config
    end

    def config
      @config ||= Configuration.new
    end

    def reset!
      @config = Configuration.new
    end
  end
end
