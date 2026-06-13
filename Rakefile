# frozen_string_literal: true

require "bundler/gem_tasks"
require "standard/rake"
require "rake/testtask"

desc "Check Gemfile.lock for vulnerable gems (updates ruby-advisory-db first)"
task :audit do
  require "bundler/audit/cli"
  Bundler::Audit::CLI.start(["check", "--update"])
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"].exclude("test/integration/**/*_test.rb")
end

namespace :test do
  Rake::TestTask.new(:integration) do |t|
    t.libs << "lib"
    t.test_files = FileList["test/integration/**/*_test.rb"]
  end

  Rake::TestTask.new(:smoke) do |t|
    t.libs << "lib"
    t.test_files = FileList["test/integration/smoke_test.rb"]
  end
end

desc "Run unit + integration tests with coverage; writes coverage/index.html"
task :coverage do
  ENV["COVERAGE"] = "1"

  # Each suite runs in its own process; distinct command names let SimpleCov
  # merge the two result sets instead of the second overwriting the first.
  ENV["COVERAGE_COMMAND"] = "unit"
  Rake::Task["test"].invoke

  ENV["COVERAGE_COMMAND"] = "integration"
  Rake::Task["test:integration"].invoke
end

task default: %i[standard test]
