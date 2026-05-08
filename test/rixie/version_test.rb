# frozen_string_literal: true

require "test_helper"

class Rixie::VersionTest < Minitest::Test
  def test_version_is_defined
    assert Rixie::VERSION
  end
end
