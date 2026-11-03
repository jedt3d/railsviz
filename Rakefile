# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.test_files = FileList["test/**/*_test.rb"].exclude("test/dummy/**/*", "test/acceptance/**/*")
end

task default: :test
