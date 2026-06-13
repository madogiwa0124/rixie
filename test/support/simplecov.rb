# frozen_string_literal: true

# Coverage bootstrap. Required at the very top of each test_helper, before
# "rixie" is loaded, so SimpleCov can instrument the library on load.
#
# Opt-in via the COVERAGE env var (see `rake coverage`). The unit and
# integration suites run as separate processes; each sets a distinct
# COVERAGE_COMMAND so SimpleCov merges their results instead of overwriting.
if ENV["COVERAGE"]
  require "simplecov"

  SimpleCov.start do
    enable_coverage :branch
    command_name ENV.fetch("COVERAGE_COMMAND", "test")
    add_filter "/test/"
    # The CLI layer is verified manually / via an integration smoke test, not
    # unit-tested (see .claude/rules/cli.md), so it is excluded from coverage.
    add_filter "rixie/cli"

    # Regression floor. The unit and integration suites run as separate
    # processes; only the integration process sees the merged result, so the
    # gate is enforced there alone (the unit-only result would be below the
    # floor and fail spuriously otherwise).
    #
    # Target: line 95% / branch 80% (CLI excluded). Do not lower these.
    if ENV["COVERAGE_COMMAND"] == "integration"
      minimum_coverage line: 95, branch: 80
    end
  end
end
