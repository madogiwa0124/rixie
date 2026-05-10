# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "minitest/autorun"
require "rixie"

module Integration
  module Helper
    # Returns true when running against a real LLM provider.
    # Set RIXIE_TEST_PROVIDER (and optionally RIXIE_TEST_MODEL) to enable.
    #
    #   RIXIE_TEST_PROVIDER=anthropic RIXIE_TEST_MODEL=claude-haiku-4-5 bundle exec rake test:integration
    def live?
      ENV.key?("RIXIE_TEST_PROVIDER")
    end

    # Builds an LLM client.
    # In dummy mode, responses are served from the given array in order.
    # In live mode, responses is ignored and a real API client is returned.
    def build_client(responses: [])
      if live?
        Rixie::LLM::Client.new(
          provider: ENV["RIXIE_TEST_PROVIDER"],
          model: ENV["RIXIE_TEST_MODEL"]
        )
      else
        Rixie::LLM::Client.new(adapter: Rixie::LLM::Adapter::Dummy.new(responses))
      end
    end

    def finish_response(content: "Done.")
      raw = {"choices" => [{"message" => {"content" => content, "tool_calls" => nil}}]}
      Rixie::LLM::Response.new(raw: raw, provider: :openai)
    end

    def tool_call_response(id:, name:, arguments: {})
      raw = {
        "choices" => [{
          "message" => {
            "content" => nil,
            "tool_calls" => [{
              "id" => id,
              "function" => {"name" => name, "arguments" => JSON.generate(arguments)}
            }]
          }
        }]
      }
      Rixie::LLM::Response.new(raw: raw, provider: :openai)
    end

    def plan_done_response(steps:)
      raw = {
        "choices" => [{
          "message" => {
            "content" => nil,
            "tool_calls" => [{
              "id" => "tc_plan",
              "function" => {
                "name" => "plan_done",
                "arguments" => JSON.generate({"steps" => steps})
              }
            }]
          }
        }]
      }
      Rixie::LLM::Response.new(raw: raw, provider: :openai)
    end
  end

  class TestCase < Minitest::Test
    include Helper

    def setup
      Rixie.reset!
    end
  end
end
