# frozen_string_literal: true

require "test_helper"
require "rake"
require "minitest/mock"

class DumpTest < Minitest::Test
  KEYS = %w[meta documents routes controllers models databases boot middleware entry_points gems warnings].freeze

  # One dump shared by the read-only tests; the sentinel is set before it runs.
  # Tests that rewrite the output reset it so the next reader dumps again.
  def self.out
    @out ||= begin
      ENV["RAILS_VIS_SENTINEL"] = "sentinel-value-xyz"
      RailsVis::Dump.new(root: RailsVis.root).call
    end
  end

  def self.reset! = @out = nil

  # load_tasks must run once per process; a second call would define every task twice.
  def self.load_tasks
    @tasks_loaded ||= (Rails.application.load_tasks; true)
  end

  def out = self.class.out
  def json_text = out.join("data.json").read
  def html = out.join("index.html").read
  def data = JSON.parse(json_text)

  def test_writes_files_and_schema
    assert_equal RailsVis.root.join("doc/rails_vis"), out
    assert out.join("index.html").file?
    assert_equal KEYS.sort, data.keys.sort
    meta = data["meta"]
    assert_equal 2, meta["schema_version"]
    assert_equal "Dummy", meta["app_name"]
    assert_equal Rails.version, meta["rails_version"]
    assert_equal RUBY_VERSION, meta["ruby_version"]
    assert_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/, meta["generated_at"])
    assert_equal %w[dirty owner repo sha url_base], meta["repo"].keys.sort
  end

  def test_html_embeds_json
    tag = '<script id="rails-vis-data" type="application/json">'
    refute_includes html, "<!--RAILS_VIS_DATA-->"
    embedded = html[/#{Regexp.escape(tag)}(.*?)<\/script>/m, 1]
    refute_nil embedded, "script tag missing"
    refute_includes embedded, "</"
    assert_equal data, JSON.parse(embedded)
  end

  # docs/escaping.md contains a literal </script>; unescaped it would close the data tag early.
  def test_script_close_in_body_is_escaped
    viewer_closes = File.read(RailsVis::Dump::VIEWER).scan("</script>").size
    assert_equal viewer_closes + 1, html.scan("</script>").size
    tag = '<script id="rails-vis-data" type="application/json">'
    embedded = html[/#{Regexp.escape(tag)}(.*?)<\/script>/m, 1]
    doc = JSON.parse(embedded)["documents"].find { |d| d["path"].end_with?("docs/escaping.md") }
    assert_equal RailsVis.root.join("docs/escaping.md").read, doc["body"]
    assert_includes doc["body"], "</script><b>injected</b>"
    assert_includes doc["body"], "<!--<script>"
    refute_includes embedded, "<"
  end

  def test_no_secret_leaks
    {"data.json" => json_text, "index.html" => html}.each do |name, text|
      refute_includes text, "secret-should-not-leak"
      refute_includes text, "sentinel-value-xyz"
      refute_includes text, "recurring-arg-sentinel"
      url = ENV["DATABASE_URL"]
      refute text.include?(url), "DATABASE_URL leaked into #{name}" if url
    end
    data["databases"].each { |d| assert_empty d.keys & %w[url host username password], d.inspect }
  end

  def test_new_sections_present
    assert_equal %w[app_initializers application credentials_keys doc_url env_keys environments framework_initializers initializer_files], data["boot"].keys.sort
    assert_equal "Rack::Sendfile", data["middleware"].first["name"]
    assert_equal %w[channels jobs mailers queue_adapter rake_tasks recurring], data["entry_points"].keys.sort
    # The dummy shares the gem's Gemfile: rails comes in through `gemspec`, so the direct entry is rails_vis.
    assert data["gems"].any? { |g| g["name"] == "rails" }
    assert data["gems"].any? { |g| g["name"] == "rails_vis" && g["direct"] }
  end

  def test_warnings_collected
    warnings = data["warnings"]
    assert(warnings.any? { |w| w["where"] == "models" && w["message"].include?("Pending") })
    assert(warnings.any? { |w| w["where"] == "controllers" && w["message"].include?("health#show") })
  end

  def test_collector_failure_becomes_warning
    boom = ->(**) { raise "boom" }
    dir = RailsVis::Collectors::Routes.stub(:new, boom) { RailsVis::Dump.new(root: RailsVis.root).call }
    result = JSON.parse(dir.join("data.json").read)
    assert_equal [], result["routes"]
    assert_includes result["warnings"], { "where" => "routes", "message" => "collector failed: RuntimeError: boom" }
    refute_empty result["models"]
  ensure
    self.class.reset!
  end

  def test_rake_task_defined_by_railtie
    self.class.load_tasks
    assert Rake::Task.task_defined?("rails_vis:dump")
  end

  def test_rake_task
    self.class.load_tasks
    dir = RailsVis.root.join("doc/rails_vis")
    FileUtils.rm_rf(dir)
    root = RailsVis.root
    RailsVis.root = nil # outside tests nothing sets it before the task runs
    task = Rake::Task["rails_vis:dump"]
    task.reenable
    task.invoke
    assert_equal root, RailsVis.root
    assert dir.join("index.html").file?
    result = JSON.parse(dir.join("data.json").read)
    refute_empty result["documents"]
    refute(result["warnings"].any? { |w| w["message"].include?("for nil") }, result["warnings"].inspect)
  ensure
    RailsVis.root = root
    self.class.reset!
  end
end
