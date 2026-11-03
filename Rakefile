# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"].exclude("test/dummy/**/*", "test/acceptance/**/*")
end

task default: :test

desc "Dump a real app from acceptance/targets.yml and check the result (exit 2 = skipped)"
task :acceptance, [:target] do |_, args|
  target = args.fetch(:target) { abort "usage: rake acceptance[target]" }
  ruby "script/acceptance.rb", target do |ok, status|
    exit status.exitstatus unless ok
  end
  sh({ "RAILS_VIS_TARGET" => target }, FileUtils::RUBY, "-Itest", "test/acceptance/acceptance_test.rb")
end
