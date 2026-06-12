# frozen_string_literal: true

require_relative "cli_test_helper"
require "optparse"
require "rixie/cli/renderer"
require "rixie/cli/tracing"

class CliTracingTest < Minitest::Test
  ENV_KEYS = %w[
    LANGFUSE_BASE_URL LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY
    OTEL_EXPORTER_OTLP_TRACES_ENDPOINT OPENOBSERVE_USER OPENOBSERVE_PASSWORD
  ].freeze

  def setup
    super
    @saved_env = ENV_KEYS.to_h { |k| [k, ENV.delete(k)] }
  end

  def teardown
    @saved_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    super
  end

  def parse_options(argv)
    options = {}
    parser = OptionParser.new
    Rixie::CLI::Tracing.add_options(parser, options)
    parser.parse!(argv)
    options
  end

  def make_tracing(options)
    Rixie::CLI::Tracing.new(options, renderer: Rixie::CLI::Renderer.new)
  end

  # --- add_options ---

  def test_langfuse_option_with_value
    options = parse_options(["--langfuse", "http://lf.example.com"])
    assert_equal "http://lf.example.com", options[:langfuse_url]
  end

  def test_langfuse_option_without_value_falls_back_to_env_then_default
    options = parse_options(["--langfuse"])
    assert_equal "http://localhost:3000", options[:langfuse_url]

    ENV["LANGFUSE_BASE_URL"] = "http://lf.env.example.com"
    options = parse_options(["--langfuse"])
    assert_equal "http://lf.env.example.com", options[:langfuse_url]
  end

  def test_otel_option_without_value_falls_back_to_env_then_default
    options = parse_options(["--otel"])
    assert_equal "http://localhost:5080/api/default/v1/traces", options[:otel_endpoint]

    ENV["OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"] = "http://otel.env.example.com/v1/traces"
    options = parse_options(["--otel"])
    assert_equal "http://otel.env.example.com/v1/traces", options[:otel_endpoint]
  end

  def test_otel_auth_options
    options = parse_options(["--otel", "--otel-user", "root", "--otel-password", "secret"])
    assert_equal "root", options[:otel_user]
    assert_equal "secret", options[:otel_password]
  end

  # --- resolution ---

  def test_disabled_when_no_options_given
    tracing = make_tracing({})

    assert_empty tracing.subscribers
    assert_empty tracing.active_endpoints
  end

  def test_langfuse_subscriber_built_when_keys_present
    ENV["LANGFUSE_PUBLIC_KEY"] = "pk"
    ENV["LANGFUSE_SECRET_KEY"] = "sk"
    tracing = make_tracing({langfuse_url: "http://lf.example.com"})

    assert_equal 1, tracing.subscribers.size
    assert_instance_of Rixie::Subscribers::Langfuse, tracing.subscribers.first
    assert_equal [["Langfuse", "http://lf.example.com"]], tracing.active_endpoints
  end

  def test_langfuse_disabled_with_error_message_when_keys_missing
    tracing = nil
    out, _err = capture_io do
      tracing = make_tracing({langfuse_url: "http://lf.example.com"})
    end

    assert_match(/LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY/, out)
    assert_empty tracing.subscribers
    assert_empty tracing.active_endpoints
  end

  def test_otel_subscriber_built_from_endpoint
    tracing = make_tracing({otel_endpoint: "http://otel.example.com/v1/traces"})

    assert_equal 1, tracing.subscribers.size
    assert_instance_of Rixie::Subscribers::OpenTelemetry, tracing.subscribers.first
    assert_equal [["OpenTelemetry", "http://otel.example.com/v1/traces"]], tracing.active_endpoints
  end

  def test_otel_basic_auth_headers_from_options
    tracing = make_tracing({otel_endpoint: "http://otel.example.com", otel_user: "root", otel_password: "secret"})

    headers = tracing.subscribers.first.instance_variable_get(:@headers)
    assert_equal "Basic #{Base64.strict_encode64("root:secret")}", headers["Authorization"]
  end

  def test_otel_basic_auth_headers_from_env
    ENV["OPENOBSERVE_USER"] = "envuser"
    ENV["OPENOBSERVE_PASSWORD"] = "envpass"
    tracing = make_tracing({otel_endpoint: "http://otel.example.com"})

    headers = tracing.subscribers.first.instance_variable_get(:@headers)
    assert_equal "Basic #{Base64.strict_encode64("envuser:envpass")}", headers["Authorization"]
  end

  def test_otel_headers_empty_without_credentials
    tracing = make_tracing({otel_endpoint: "http://otel.example.com"})

    assert_empty tracing.subscribers.first.instance_variable_get(:@headers)
  end

  def test_both_backends_active_together
    ENV["LANGFUSE_PUBLIC_KEY"] = "pk"
    ENV["LANGFUSE_SECRET_KEY"] = "sk"
    tracing = make_tracing({langfuse_url: "http://lf.example.com", otel_endpoint: "http://otel.example.com"})

    assert_equal 2, tracing.subscribers.size
    assert_instance_of Rixie::Subscribers::Langfuse, tracing.subscribers[0]
    assert_instance_of Rixie::Subscribers::OpenTelemetry, tracing.subscribers[1]
    assert_equal [["Langfuse", "http://lf.example.com"], ["OpenTelemetry", "http://otel.example.com"]],
      tracing.active_endpoints
  end
end
