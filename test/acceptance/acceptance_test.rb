# frozen_string_literal: true

# Checks the report and data.json written by script/acceptance.rb for ENV["RAILS_VIS_TARGET"].
# Not part of `rake test`; run by `rake acceptance[target]`.
require "minitest/autorun"
require "json"
require "yaml"

class AcceptanceTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  TARGET = ENV.fetch("RAILS_VIS_TARGET")
  SPEC = YAML.load_file(File.join(ROOT, "acceptance/targets.yml")).fetch(TARGET)
  REPORT = File.join(ROOT, "tmp/acceptance/#{TARGET}.report.json")
  DATA = File.join(ROOT, "tmp/acceptance", TARGET, SPEC["app_dir"], "doc/rails_vis/data.json")
  COLLECTORS = %w[routes controllers models databases documents boot middleware entry_points gems].freeze

  def report = @report ||= JSON.parse(File.read(REPORT, encoding: "UTF-8"))
  def text = @text ||= File.read(DATA, encoding: "UTF-8")
  def data = @data ||= JSON.parse(text)

  def test_floors
    assert_operator report["routes"], :>=, SPEC["floors"]["routes"]
    assert_operator report["models"], :>=, SPEC["floors"]["models"]
    assert_operator report["controllers"], :>, 0
  end

  def test_no_secrets
    # DB_HOST ("localhost") may legitimately appear elsewhere, so it is checked against databases only.
    databases = JSON.generate(data["databases"])
    # All three match as whole words: dev containers commonly use a token such as "postgres" for the user and the password,
    # and it is a substring of "postgresql" (adapter names, README text such as "postgresql@14"). A whole-word match still
    # catches a real password embedded as a value; the key assertion below guards the direct path (no password/username/host/url keys).
    word = ->(haystack, value) { haystack.match?(/(?<![A-Za-z0-9_])#{Regexp.escape(value)}(?![A-Za-z0-9_])/) }
    { "DB_USER" => text, "DB_PASS" => text, "DB_HOST" => databases }.each do |key, haystack|
      value = (SPEC["env"] || {})[key] || ENV[key]
      refute word.call(haystack, value), "#{key} value leaked into data.json" if value && !value.empty?
    end
    data["databases"].each { |d| assert_empty d.keys & %w[password username host url], d.inspect }
  end

  def test_links
    assert_equal 10, report["links_checked"], report["links"].inspect
    assert_equal 10, report["links_ok"], report["links"].inspect
  end

  # Dump#run turns a raising collector into an empty list plus a warning under the collector's name.
  # Per-node warnings share that `where`, so a whole-collector failure is "warned and empty".
  def test_no_collector_failed
    COLLECTORS.each do |name|
      warned = data["warnings"].select { |w| w["where"] == name }
      refute(data[name].empty? && warned.any?, "collector #{name} failed: #{warned.inspect}")
    end
  end

  # Gem-drawn routes (turbo-rails, Active Storage under /files) are kept with source nil and no engine.
  def test_new_sections_have_content
    assert_operator data["middleware"].size, :>=, 10
    assert_operator data["gems"].size, :>=, 20
    # An engine's dummy app may have no initializer files; its environments are always there.
    key = TARGET == "spina" ? "environments" : "initializer_files"
    refute_empty data["boot"][key]
  end

  def test_spina_routes_are_engine_routes
    skip unless TARGET == "spina"
    others = data["routes"].select { |r| r["source"] && r["engine"] != "Spina::Engine" }
    assert_empty others.map { |r| "#{r["verb"]} #{r["path"]} (#{r["engine"].inspect})" }
    assert_operator data["routes"].count { |r| r["engine"] == "Spina::Engine" }, :>=, 100
  end

  def test_spina_route_sources_are_repo_config
    skip unless TARGET == "spina"
    bad = data["routes"].select { |r| r["source"] && !r["source"]["path"].start_with?("config/") }
    assert_empty bad.map { |r| "#{r["verb"]} #{r["path"]}: #{r["source"].inspect}" }
  end

  def test_spina_models_and_paths
    skip unless TARGET == "spina"
    assert_includes data["models"].map { |m| m["name"] }, "Spina::Page"
    # Repo-relative: the engine's own classes sit under app/ at the repository root; the dummy's
    # ApplicationController really is at test/dummy/app/, so every path must name a file in the clone.
    clone = File.join(ROOT, "tmp/acceptance", TARGET)
    (data["controllers"] + data["models"]).each do |node|
      path = node["source"]["path"]
      assert File.file?(File.join(clone, path)), "#{node["name"]}: #{path} is not repo-relative"
      assert path.start_with?("app/"), "#{node["name"]}: #{path}" if node["name"].start_with?("Spina::")
    end
  end

  def test_lobsters
    skip unless TARGET == "lobsters"
    dev = data["databases"].select { |d| d["env"] == "development" }.to_h { |d| [d["name"], d] }
    assert_empty %w[primary cache queue rack_attack] - dev.keys
    assert_equal "solid_cache", dev["cache"]["solid_component"]
    assert_equal "solid_queue", dev["queue"]["solid_component"]
  end

  def test_mastodon
    skip unless TARGET == "mastodon"
    assert(data["databases"].any? { |d| d["env"] == "development" && d["name"] == "replica" })
  end
end
