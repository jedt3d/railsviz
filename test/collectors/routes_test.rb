# frozen_string_literal: true

require "test_helper"

class RoutesCollectorTest < Minitest::Test
  def result = @result ||= RailsVis::Collectors::Routes.new(repo: RailsVis::Repo.detect(RailsVis.root)).call
  def routes = result["routes"]
  def find(path, action: nil) = routes.find { |r| r["path"] == path && (action.nil? || r["action"] == action) }

  def test_routes_have_source_line
    route = find("/patients", action: "index")
    line = File.readlines(RailsVis.root.join("config/routes.rb")).index { |l| l.include?("resources :patients") } + 1
    assert_equal "test/dummy/config/routes.rb", route["source"]["path"]
    assert_equal line, route["source"]["line"]
  end

  def test_internal_routes_excluded
    assert routes.none? { |r| r["path"].start_with?("/rails/") }
  end

  def test_verb_path_controller_action
    route = find("/health")
    assert_equal "GET", route["verb"]
    assert_equal "health", route["controller"]
    assert_equal "show", route["action"]
    assert_nil route["engine"]
  end

  def test_doc_url
    assert routes.all? { |r| r["doc_url"] == RailsVis::DocLinks.routing }
  end

  def test_engine_routes_expanded
    route = find("/blog/posts")
    assert_equal "blog/posts", route["controller"]
    assert_equal "Blog::Engine", route["engine"]
    assert routes.none? { |r| r["path"] == "/blog" && r["action"].nil? }
  end

  def test_engine_route_source
    route = find("/blog/posts")
    assert_equal "test/dummy/engines/blog/config/routes.rb", route["source"]["path"]
    assert_equal 2, route["source"]["line"]
    assert result["warnings"].none? { |w| w["message"].include?("/blog/posts") }
  end
end
