# frozen_string_literal: true

require "bundler/gem_tasks"
require "standard/rake"
require "rake/testtask"

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

task default: %i[standard test]
