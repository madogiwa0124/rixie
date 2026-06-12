# frozen_string_literal: true

module Rixie
  class CLI
    class Tracing
      # Resolves the optional OpenTelemetry subscriber from CLI options and
      # environment variables.
      class Otel
        def self.add_options(parser, options)
          parser.on("--otel [ENDPOINT]", "Enable OpenTelemetry tracing (default: http://localhost:5080/api/default/v1/traces)") do |v|
            options[:otel_endpoint] = v || ENV.fetch("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", "http://localhost:5080/api/default/v1/traces")
          end

          parser.on("--otel-user USER", "Basic auth username for OTel backend (e.g. OpenObserve)") do |v|
            options[:otel_user] = v
          end

          parser.on("--otel-password PASSWORD", "Basic auth password for OTel backend") do |v|
            options[:otel_password] = v
          end
        end

        attr_reader :subscriber

        def initialize(options, renderer:)
          @options = options
          @renderer = renderer
          @subscriber = resolve
        end

        def label = "OpenTelemetry"

        # Display value for the welcome banner — nil when inactive.
        def endpoint
          @subscriber && @options[:otel_endpoint]
        end

        private

        def resolve
          endpoint = @options[:otel_endpoint]
          return nil unless endpoint

          Rixie::Subscribers::OpenTelemetry.new(service_name: "rixie", endpoint: endpoint, headers: headers)
        end

        def headers
          user = @options[:otel_user] || ENV["OPENOBSERVE_USER"]
          password = @options[:otel_password] || ENV["OPENOBSERVE_PASSWORD"]
          return {} unless user && password

          require "base64"
          {"Authorization" => "Basic #{Base64.strict_encode64("#{user}:#{password}")}"}
        end
      end
    end
  end
end
