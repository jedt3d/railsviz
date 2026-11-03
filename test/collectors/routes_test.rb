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

  # Active Storage draws under routes_prefix "/files" from its gem routes file: kept, no app source line.
  def test_gem_drawn_routes_kept_without_source
    files = routes.select { |r| r["path"].start_with?("/files/") }
    refute_empty files
    assert files.all? { |r| r["source"].nil? }, files.inspect
    refute_nil find("/blog/posts")["source"]
    collapsed = result["warnings"].select { |w| w["message"].match?(/\d+ routes drawn by .*active_?storage.*routes\.rb/i) }
    assert_equal 1, collapsed.size, result["warnings"].inspect
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
