# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "tmpdir"
require "rake"

# The rake CLI records `desc` text; other tests call load_tasks first, so switch it on at load time like the CLI does.
Rake::TaskManager.record_task_metadata = true

class EntryPointsCollectorTest < Minitest::Test
  def result = @result ||= RailsVis::Collectors::EntryPoints.new(repo: RailsVis::Repo.detect(RailsVis.root)).call
  def ep = result["entry_points"]
  def line_of(file, text) = File.readlines(RailsVis.root.join(file)).index { |l| l.include?(text) } + 1

  def test_jobs
    assert_equal "test", ep["queue_adapter"]
    welcome = ep["jobs"].find { |j| j["name"] == "WelcomeJob" }
    assert_equal "mailers", welcome["queue"]
    assert_equal "test/dummy/app/jobs/welcome_job.rb", welcome["source"]["path"]
    assert_nil ep["jobs"].find { |j| j["name"] == "ApplicationJob" }["queue"]
    assert ep["jobs"].all? { |j| j["doc_url"] == RailsVis::DocLinks.active_job }
  end

  def test_recurring_without_args
    names = ep["recurring"].map { |r| [r["env"], r["name"]] }
    assert_equal [%w[production cleanup], %w[production nightly_report]], names.sort
    nightly = ep["recurring"].find { |r| r["name"] == "nightly_report" }
    assert_equal({ "class" => "WelcomeJob", "command" => nil, "queue" => "background", "schedule" => "every day at 2am" }, nightly.slice("class", "command", "queue", "schedule"))
    assert_equal line_of("config/recurring.yml", "nightly_report:"), nightly["source"]["line"]
    refute_includes JSON.generate(ep), "recurring-arg-sentinel"
  end

  def recurring_with(content)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config/recurring.yml"), content) if content
      Rails.stub(:root, Pathname.new(dir)) do
        collector = RailsVis::Collectors::EntryPoints.new(repo: RailsVis::Repo.detect(RailsVis.root))
        [collector.send(:recurring), collector.instance_variable_get(:@warnings)]
      end
    end
  end

  def test_recurring_absent_is_empty_without_warning
    assert_equal [[], []], recurring_with(nil)
  end

  def test_recurring_malformed_warns_once
    rows, warnings = recurring_with("production: [unclosed")
    assert_equal [], rows
    assert_equal 1, warnings.size
    assert_match(/\Arecurring: config\/recurring\.yml: /, warnings.first["message"])
  end

  def test_mailers_and_templates
    mailer = ep["mailers"].find { |m| m["name"] == "PatientMailer" }
    assert_equal %w[reminder welcome], mailer["actions"].map { |a| a["name"] }
    welcome = mailer["actions"].find { |a| a["name"] == "welcome" }
    assert_equal line_of("app/mailers/patient_mailer.rb", "def welcome"), welcome["source"]["line"]
    assert_equal ["test/dummy/app/views/patient_mailer/welcome.text.erb"], welcome["templates"].map { |t| t["path"] }
    assert_equal [], mailer["actions"].find { |a| a["name"] == "reminder" }["templates"]
  end

  def test_channels
    assert_equal %w[ApplicationCable::Channel VisitsChannel], ep["channels"].map { |c| c["name"] }
    assert_equal "test/dummy/app/channels/visits_channel.rb", ep["channels"].last["source"]["path"]
  end

  def test_rake_tasks_under_app_root_only
    assert_equal ["dummy:report"], ep["rake_tasks"].map { |t| t["name"] }
    task = ep["rake_tasks"].first
    assert_equal "Prints a report", task["comment"]
    assert_equal "test/dummy/lib/tasks/dummy.rake", task["source"]["path"]
    assert_equal line_of("lib/tasks/dummy.rake", "task report:"), task["source"]["line"]
  end
end
