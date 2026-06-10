# frozen_string_literal: true

require_relative "rixie/version"
require_relative "rixie/error"
require_relative "rixie/http/client"
require_relative "rixie/configuration"
require_relative "rixie/event"
require_relative "rixie/event_listener"
require_relative "rixie/subscriber"
require_relative "rixie/subscribers/event_severity"
require_relative "rixie/subscribers/logger"
require_relative "rixie/subscribers/json_logger"
require_relative "rixie/subscribers/langfuse"
require_relative "rixie/llm/tool_call"
require_relative "rixie/message"
require_relative "rixie/llm/response"
require_relative "rixie/llm/client"
require_relative "rixie/llm/adapter/dummy"
require_relative "rixie/tool"
require_relative "rixie/tool/human_input"
require_relative "rixie/tool/fetch"
require_relative "rixie/tool/current_time"
require_relative "rixie/tool/calculator"
require_relative "rixie/tool/file_read"
require_relative "rixie/tool/file_list"
require_relative "rixie/tool/file_search"
require_relative "rixie/tool_executor"
require_relative "rixie/prompt_builder"
require_relative "rixie/token_counter"
require_relative "rixie/context/history"
require_relative "rixie/context/plan"
require_relative "rixie/context/summary"
require_relative "rixie/agent"
require_relative "rixie/agent/plan"
require_relative "rixie/agent/re_act"
require_relative "rixie/agent/compressor"
require_relative "rixie/store/base"
require_relative "rixie/store/memory"
require_relative "rixie/store/null"
require_relative "rixie/run"
require_relative "rixie/strategy/simple"
require_relative "rixie/strategy/plan_execute"
require_relative "rixie/strategy/re_act"
require_relative "rixie/task"
require_relative "rixie/session"
require_relative "rixie/mcp"
require_relative "rixie/search/base"
require_relative "rixie/search/duck_duck_go"
require_relative "rixie/search/wikipedia"
require_relative "rixie/tool/web_search"
require_relative "rixie/tool/wikipedia_search"

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

    def logger
      config.logger
    end
  end
end
