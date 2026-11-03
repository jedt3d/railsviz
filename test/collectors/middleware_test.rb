# frozen_string_literal: true

require "test_helper"

class MiddlewareCollectorTest < Minitest::Test
  def result = @result ||= RailsVis::Collectors::Middleware.new(repo: RailsVis::Repo.detect(RailsVis.root)).call
  def rows = result["middleware"]
  def find(name) = rows.find { |m| m["name"] == name }

  def test_order_and_gem_attribution
    assert_equal "Rack::Sendfile", rows.first["name"]
    assert_equal({ "name" => "rack", "version" => Gem.loaded_specs["rack"].version.to_s }, rows.first["gem"])
    assert_nil rows.first["source"]["path"]
    assert_match %r{\Ahttps://}, rows.first["source"]["url"]
    assert_equal "actionpack", find("ActionDispatch::Static")["gem"]["name"]
    assert_operator rows.index { |m| m["name"] == "ActionDispatch::Static" }, :<, rows.index { |m| m["name"] == "ActionDispatch::Cookies" }
  end

  def test_app_middleware_has_no_gem_and_an_app_source
    stamp = find("RequestStamp")
    assert_nil stamp["gem"]
    assert_equal "test/dummy/app/middleware/request_stamp.rb", stamp["source"]["path"]
    assert_equal 2, stamp["source"]["line"]
  end

  def test_module_middleware_is_kept
    cache = find("ActiveSupport::Cache::Strategy::LocalCache")
    refute_nil cache
    assert_equal "activesupport", cache["gem"]["name"]
    assert_empty result["warnings"].select { |w| w["message"].include?("LocalCache") }
  end

  def test_no_arguments_written
    assert rows.all? { |m| m.keys.sort == %w[doc_url gem name source] }, rows.map(&:keys).uniq.inspect
    assert rows.all? { |m| m["doc_url"] == RailsVis::DocLinks.rails_on_rack }
  end

  def test_nameless_entry_is_kept_without_breaking_the_stack
    stack = Rails.application.middleware.to_a + [ActionDispatch::MiddlewareStack::Middleware.new(proc { |_env| [200, {}, []] }, [], nil)]
    out = RailsVis::Collectors::Middleware.new(repo: RailsVis::Repo.detect(RailsVis.root), stack: stack).call
    assert_equal rows, out["middleware"].first(rows.size)
    assert_equal({ "name" => "Proc", "gem" => nil, "source" => nil, "doc_url" => RailsVis::DocLinks.rails_on_rack }, out["middleware"].last)
    assert_empty out["warnings"]
  end
end
