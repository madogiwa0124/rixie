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
          },
          "ollama" => {
            adapter: :openai,
            base_url: "http://localhost:11434/v1",
            api_key: -> { "ollama" }
          }
        }.freeze

        def self.resolve(model: nil, provider: nil, request_timeout: nil, temperature: nil, parallel_tool_calls: nil, provider_params: nil)
          raise Rixie::NoProviderError, "No provider configured. Pass `provider:` or set Rixie.config.default_provider." if provider.nil?

          all_providers = BUILTIN_PROVIDERS.merge(Rixie.config.custom_providers)
          config = all_providers[provider.to_s]
          raise Rixie::UnknownProviderError, "Unknown provider: #{provider.inspect}" if config.nil?

          api_key = config[:api_key]
          api_key = api_key.call if api_key.respond_to?(:call)

          adapter_class = adapter_class_for(config[:adapter])
          params = {
            model: model,
            base_url: config[:base_url],
            api_key: api_key,
            request_timeout: request_timeout,
            temperature: temperature,
            provider_params: provider_params
          }
          params[:parallel_tool_calls] = parallel_tool_calls unless parallel_tool_calls.nil? || !openai_adapter?(adapter_class)
          adapter_class.new(**params)
        end

        # Adapter::OpenAI is loaded lazily; when resolving a custom adapter class
        # the constant may not be defined, so it must not be referenced unguarded.
        def self.openai_adapter?(adapter_class)
          defined?(Adapter::OpenAI) ? adapter_class <= Adapter::OpenAI : false
        end
        private_class_method :openai_adapter?

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
