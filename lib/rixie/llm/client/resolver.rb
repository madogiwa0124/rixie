# frozen_string_literal: true

module Rixie
  module LLM
    class Client
      class Resolver
        BUILTIN_PROVIDERS = {
          "openai" => {
            adapter: :openai,
            base_url: "https://api.openai.com/v1",
            api_key: -> { ENV["OPENAI_API_KEY"] }
          }
        }.freeze

        def self.resolve(model: nil, provider: nil, request_timeout: nil, max_tokens: nil, temperature: nil)
          raise Rixie::NoProviderError, "No provider configured. Pass `provider:` or set Rixie.config.default_provider." if provider.nil?

          all_providers = BUILTIN_PROVIDERS.merge(Rixie.config.custom_providers)
          config = all_providers[provider.to_s]
          raise Rixie::UnknownProviderError, "Unknown provider: #{provider.inspect}" if config.nil?

          api_key = config[:api_key]
          api_key = api_key.call if api_key.respond_to?(:call)

          adapter_class_for(config[:adapter]).new(
            model: model,
            base_url: config[:base_url],
            api_key: api_key,
            request_timeout: request_timeout,
            max_tokens: max_tokens,
            temperature: temperature
          )
        end

        def self.adapter_class_for(adapter)
          case adapter
          when :openai
            require_relative "../adapter/openai"
            Adapter::OpenAI
          when Class
            adapter
          else
            raise Rixie::ConfigurationError, "Unknown adapter: #{adapter.inspect}"
          end
        end
        private_class_method :adapter_class_for
      end
    end
  end
end
