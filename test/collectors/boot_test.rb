# frozen_string_literal: true

require "test_helper"

class BootCollectorTest < Minitest::Test
  def result = @result ||= RailsVis::Collectors::Boot.new(repo: RailsVis::Repo.detect(RailsVis.root)).call
  def boot = result["boot"]
  def line_of(file, text) = File.readlines(RailsVis.root.join(file)).index { |l| l.include?(text) } + 1

  def test_application_and_environments
    assert_equal "test/dummy/config/application.rb", boot["application"]["path"]
    assert_equal line_of("config/application.rb", "class Application"), boot["application"]["line"]
    assert_equal %w[development production test], boot["environments"].map { |n| n["name"] }
    assert_equal "test/dummy/config/environments/test.rb", boot["environments"].last["path"]
  end

  def test_initializer_files_in_load_order
    assert_equal %w[content_security_policy filter_parameter_logging inflections], boot["initializer_files"].map { |n| n["name"] }
    assert boot["initializer_files"].all? { |n| n["path"].start_with?("test/dummy/config/initializers/") && n["line"] == 1 }
  end

  def test_app_initializer_links_to_its_block
    marker = boot["app_initializers"].find { |i| i["name"] == "dummy_marker" }
    assert_equal "Dummy::Application", marker["railtie"]
    assert_equal "test/dummy/config/application.rb", marker["source"]["path"]
    assert_equal line_of("config/application.rb", "initializer :dummy_marker"), marker["source"]["line"]
    assert boot["app_initializers"].all? { |i| i["source"]["path"].start_with?("test/dummy/") }
  end

  def test_framework_initializers_are_counted_per_railtie
    ar = boot["framework_initializers"].find { |f| f["railtie"] == "ActiveRecord::Railtie" }
    assert_operator ar["count"], :>, 10
    assert_match %r{\Ahttps://}, ar["url"]
    assert boot["framework_initializers"].none? { |f| f["railtie"] == "Dummy::Application" && f["url"].nil? }, "Rails' own application-context initializers come from railties and link to it"
  end

  def test_env_keys_are_keys_with_references_only
    db = boot["env_keys"].find { |e| e["key"] == "DATABASE_URL" }
    ref = db["references"].first
    assert_equal "test/dummy/config/database.yml", ref["path"]
    assert_equal line_of("config/database.yml", "DATABASE_URL"), ref["line"]
    assert_equal boot["env_keys"].map { |e| e["key"] }, boot["env_keys"].map { |e| e["key"] }.sort
    refute_includes JSON.generate(boot), ENV.fetch("RAILS_VIS_DB", "sqlite3-sentinel-never-written")
  end

  def test_credentials_without_master_key
    assert_nil boot["credentials_keys"]
    assert result["warnings"].any? { |w| w["message"].include?("no master key") }, result["warnings"].inspect
  end

  def test_doc_url
    assert_equal RailsVis::DocLinks.guide("configuring"), boot["doc_url"]
  end
end
