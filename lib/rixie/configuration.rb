# frozen_string_literal: true

require "logger"

module Rixie
  class Configuration
    attr_accessor :default_provider, :default_model, :default_max_steps, :store, :logger, :log_level, :request_timeout, :default_max_tokens, :default_temperature

    def initialize
      @default_provider = nil
      @default_model = nil
      @default_max_steps = 10
      @store = nil
      @logger = Logger.new($stdout)
      @log_level = :info
      @request_timeout = nil
      @default_max_tokens = nil
      @default_temperature = nil
      @custom_providers = {}
    end

    def register_provider(name, adapter:, base_url:, api_key:)
      @custom_providers[name.to_s] = {adapter: adapter, base_url: base_url, api_key: api_key}
    end

    attr_reader :custom_providers
  end
end
