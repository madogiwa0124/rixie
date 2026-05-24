# frozen_string_literal: true

require_relative "lib/rixie/version"

Gem::Specification.new do |spec|
  spec.name = "rixie"
  spec.version = Rixie::VERSION
  spec.authors = ["madogiwa0124"]
  spec.email = ["madogiwa0124@gmail.com"]

  spec.summary = "AI agent orchestration for Ruby"
  spec.description = "Rixie is a standalone Ruby gem for orchestrating AI agents. It provides a clean abstraction for LLM communication, tool execution, and multi-step reasoning strategies."
  spec.homepage = "https://github.com/madogiwa0124/rixie"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/console bin/setup Gemfile .gitignore .github/ .standard.yml])
    end
  end
  spec.bindir = "bin"
  spec.executables = ["rixie"]
  spec.require_paths = ["lib"]

  spec.add_dependency "logger"

  # Optional dependencies. Loaded lazily and raise Rixie::ConfigurationError if missing.
  #   cli-ui   — required for the `rixie` CLI
  #   nokogiri — required for Tool::Fetch and Search::DuckDuckGo
  #   openai   — required for the openai/ollama provider adapter

  # Development dependencies are declared in the Gemfile.
end
