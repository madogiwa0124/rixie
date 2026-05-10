# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift File.expand_path("support/fake_gems", __dir__)

require "minitest/autorun"
require "rixie"

module Minitest
  class Test
    def setup
      Rixie.reset!
    end
  end
end
