# frozen_string_literal: true

module Rixie
  class Error < StandardError; end

  class ConfigurationError < Error; end
  class NoProviderError < ConfigurationError; end
  class UnknownProviderError < ConfigurationError; end

  class NotImplementedError < Error; end

  class AgentError < Error; end
  class MaxStepsExceededError < AgentError; end
  class ToolNotFoundError < AgentError; end

  module LLM
    class Error < ::Rixie::Error; end
    class ResponseTruncatedError < Error; end
  end

  module Http
    class Error < ::Rixie::Error; end
    class TimeoutError < Error; end
    class ConnectionError < Error; end
    class SSRFError < Error; end
  end

  module MCP
    class Error < ::Rixie::Error; end
    class TimeoutError < Error; end
    class ProtocolError < Error; end
    class RequestError < Error; end
  end
end
