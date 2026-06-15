# frozen_string_literal: true

require_relative "../support/simplecov"

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "minitest/autorun"
require "rixie"

module Integration
  module Helper
    # Returns true when running against a real LLM provider.
    #
    # Built-in provider (openai, ollama):
    #   RIXIE_TEST_PROVIDER=openai RIXIE_TEST_MODEL=gpt-4.1-mini bundle exec rake test:integration
    #
    # OpenAI-compatible endpoint (Ollama, etc.):
    #   RIXIE_TEST_BASE_URL=http://localhost:11434/v1 RIXIE_TEST_MODEL=qwen3.5:4b bundle exec rake test:integration
    def live?
      ENV.key?("RIXIE_TEST_PROVIDER") || ENV.key?("RIXIE_TEST_BASE_URL")
    end

    # Builds an LLM client.
    # In dummy mode, responses are served from the given array in order.
    # In live mode, responses is ignored and a real API client is returned.
    #
    # RIXIE_TEST_BASE_URL registers a temporary "custom" provider using the
    # openai adapter, which works with any OpenAI-compatible endpoint (Ollama, etc.).
    # RIXIE_TEST_API_KEY defaults to "ollama" (Ollama ignores the key).
    def build_client(responses: [])
      timeout = ENV["RIXIE_TEST_REQUEST_TIMEOUT"]&.to_i

      if ENV.key?("RIXIE_TEST_BASE_URL")
        register_custom_provider
        Rixie::LLM::Client.new(provider: "custom", model: ENV["RIXIE_TEST_MODEL"], request_timeout: timeout)
      elsif ENV.key?("RIXIE_TEST_PROVIDER")
        Rixie::LLM::Client.new(provider: ENV["RIXIE_TEST_PROVIDER"], model: ENV["RIXIE_TEST_MODEL"], request_timeout: timeout)
      else
        Rixie::LLM::Client.new(adapter: Rixie::LLM::Adapter::Dummy.new(responses))
      end
    end

    def finish_response(content: "Done.")
      {"choices" => [{"message" => {"content" => content, "tool_calls" => nil}}]}
    end

    def tool_call_response(id:, name:, arguments: {})
      {
        "choices" => [{
          "message" => {
            "content" => nil,
            "tool_calls" => [{"id" => id, "function" => {"name" => name, "arguments" => JSON.generate(arguments)}}]
          }
        }]
      }
    end

    # Builds a streaming LLM client.
    # In dummy mode, responses are served from the given array in order.
    # In live mode, returns a real streaming client against the configured provider.
    def build_stream_client(responses: [])
      timeout = ENV["RIXIE_TEST_REQUEST_TIMEOUT"]&.to_i

      if ENV.key?("RIXIE_TEST_BASE_URL")
        register_custom_provider
        Rixie::LLM::Client.new(provider: "custom", model: ENV["RIXIE_TEST_MODEL"], stream: true, request_timeout: timeout)
      elsif ENV.key?("RIXIE_TEST_PROVIDER")
        Rixie::LLM::Client.new(provider: ENV["RIXIE_TEST_PROVIDER"], model: ENV["RIXIE_TEST_MODEL"], stream: true, request_timeout: timeout)
      else
        Rixie::LLM::Client.new(adapter: Rixie::LLM::Adapter::Dummy.new(responses), stream: true)
      end
    end

    private

    def register_custom_provider
      Rixie.configure do |c|
        c.register_provider("custom",
          adapter: :openai,
          base_url: ENV["RIXIE_TEST_BASE_URL"],
          api_key: ENV.fetch("RIXIE_TEST_API_KEY", "ollama"))
      end
    end

    # The plan phase uses structured output, so the planning LLM turn is a normal
    # finish whose content is a JSON object matching `Agent::Plan::PLAN_SCHEMA`.
    def plan_response(steps:)
      finish_response(content: JSON.generate({"steps" => steps}))
    end
  end

  class TestCase < Minitest::Test
    include Helper

    def setup
      Rixie.reset!
      Rixie.config.logger = Logger.new($stdout) if live?
    end
  end
end
