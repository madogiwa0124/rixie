# frozen_string_literal: true

require "logger"

module Rixie
  class Configuration
    LOG_FORMATS = %i[text json].freeze

    attr_accessor :default_provider, :default_model, :default_max_steps, :store, :request_timeout, :default_max_tokens, :default_temperature, :default_subscribers
    attr_reader :log_level, :logger, :log_format

    def log_level=(level)
      @log_level = level
      @logger&.level = ::Logger.const_get(level.to_s.upcase)
    end

    def logger=(new_logger)
      @logger = new_logger
      @logger&.level = ::Logger.const_get(@log_level.to_s.upcase)
    end

    def log_format=(format)
      sym = format.to_sym
      unless LOG_FORMATS.include?(sym)
        raise ConfigurationError, "Unknown log_format: #{format.inspect} (expected one of #{LOG_FORMATS.inspect})"
      end
      @log_format = sym
    end

    def initialize
      @default_provider = nil
      @default_model = nil
      @default_max_steps = 10
      @store = nil
      @log_level = :info
      @log_format = :text
      @logger = Logger.new($stdout).tap do |l|
        l.level = ::Logger.const_get(@log_level.to_s.upcase)
        l.formatter = proc { |severity, datetime, _progname, msg|
          "#{datetime.strftime("%Y-%m-%d %H:%M:%S.%3N")} #{severity} #{msg}\n"
        }
      end
      @request_timeout = nil
      @default_max_tokens = nil
      @default_temperature = nil
      @default_subscribers = nil
      @custom_providers = {}
    end

    def register_provider(name, adapter:, base_url:, api_key:)
      @custom_providers[name.to_s] = {adapter: adapter, base_url: base_url, api_key: api_key}
    end

    attr_reader :custom_providers
  end
end
