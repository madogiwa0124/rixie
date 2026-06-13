# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def test_configure_block_sets_values
    Rixie.configure do |config|
      config.default_provider = "anthropic"
      config.log_level = :debug
    end

    assert_equal "anthropic", Rixie.config.default_provider
    assert_equal :debug, Rixie.config.log_level
  end

  def test_register_provider_stores_custom_provider
    Rixie.configure do |config|
      config.register_provider("my_proxy",
        adapter: :openai,
        base_url: "https://my-llm-proxy.internal/v1",
        api_key: "secret")
    end

    provider = Rixie.config.custom_providers["my_proxy"]
    assert_equal :openai, provider[:adapter]
    assert_equal "https://my-llm-proxy.internal/v1", provider[:base_url]
    assert_equal "secret", provider[:api_key]
  end

  def test_reset_restores_defaults
    Rixie.configure do |config|
      config.default_provider = "openai"
      config.log_level = :debug
    end

    Rixie.reset!

    assert_nil Rixie.config.default_provider
    assert_equal :info, Rixie.config.log_level
    assert_empty Rixie.config.custom_providers
  end

  def test_default_logger_is_stdout
    assert_instance_of Logger, Rixie.config.logger
  end

  def test_default_log_level_is_applied_to_logger
    assert_equal Logger::INFO, Rixie.config.logger.level
  end

  def test_log_level_setter_updates_logger_level
    Rixie.config.log_level = :debug
    assert_equal :debug, Rixie.config.log_level
    assert_equal Logger::DEBUG, Rixie.config.logger.level
  end

  def test_default_store_is_nil
    assert_nil Rixie.config.store
  end

  def test_default_temperature_is_nil
    assert_nil Rixie.config.default_temperature
  end

  def test_configure_block_sets_temperature
    Rixie.configure do |config|
      config.default_temperature = 0.7
    end

    assert_equal 0.7, Rixie.config.default_temperature
  end

  def test_log_level_setter_with_nil_logger_does_not_raise
    Rixie.config.logger = nil
    Rixie.config.log_level = :debug
    assert_equal :debug, Rixie.config.log_level
  end

  def test_logger_setter_with_nil_clears_logger
    Rixie.config.logger = nil
    assert_nil Rixie.config.logger
  end
end
