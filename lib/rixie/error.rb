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

  class LLMError < Error; end
end
