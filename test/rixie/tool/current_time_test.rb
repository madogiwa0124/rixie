# frozen_string_literal: true

require "test_helper"

class Rixie::Tool::CurrentTimeTest < Minitest::Test
  def test_is_a_tool_instance
    assert_instance_of Rixie::Tool, Rixie::Tool::CurrentTime
  end

  def test_tool_name_is_current_time
    assert_equal "current_time", Rixie::Tool::CurrentTime.name
  end

  def test_returns_iso8601_string_by_default
    output = Rixie::Tool::CurrentTime.call({})
    assert_kind_of String, output
    parsed = Time.iso8601(output)
    assert_in_delta Time.now.to_f, parsed.to_f, 5.0
  end

  def test_returns_utc_when_timezone_utc
    output = Rixie::Tool::CurrentTime.call({"timezone" => "utc"})
    assert_match(/[Zz]\z|[+-]00:00\z/, output)
  end

  def test_returns_local_when_timezone_local
    output = Rixie::Tool::CurrentTime.call({"timezone" => "local"})
    parsed = Time.iso8601(output)
    assert_in_delta Time.now.to_f, parsed.to_f, 5.0
  end

  def test_accepts_symbol_keys
    output = Rixie::Tool::CurrentTime.call({timezone: "utc"})
    assert_match(/[Zz]\z|[+-]00:00\z/, output)
  end

  def test_unknown_timezone_falls_back_to_local
    output = Rixie::Tool::CurrentTime.call({"timezone" => "bogus"})
    parsed = Time.iso8601(output)
    assert_in_delta Time.now.to_f, parsed.to_f, 5.0
  end
end
