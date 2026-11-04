# frozen_string_literal: true

require "test_helper"

class PagesCollectorTest < Minitest::Test
  def result
    @result ||= begin
      repo = RailsVis::Repo.detect(RailsVis.root)
      routes = RailsVis::Collectors::Routes.new(repo: repo).call["routes"]
      config = RailsVis::Config.load(RailsVis.root)
      controllers = RailsVis::Collectors::Controllers.new(repo: repo, config: config, routes: routes, model_names: ["Patient"]).call["controllers"]
      RailsVis::Collectors::Pages.new(repo: repo, routes: routes, controllers: controllers).call
    end
  end

  def page(controller, action) = result["pages"].find { |p| p["controller"] == controller && p["action"] == action }
  def links(p) = p["links"].map { |l| [l["stem"], l["engine"], l["form"], l["source"]["path"], l["source"]["line"]] }

  def test_links_from_template_and_partial
    p = page("PatientsController", "index")
    assert_equal "test/dummy/app/views/patients/index.html.erb", p["template"]["path"]
    assert_equal "html", p["format"]
    assert_equal "application", p["layout"]
    assert_equal ["test/dummy/app/views/patients/_row.html.erb"], p["partials"].map { |n| n["path"] }
    assert_equal [["patient", nil, false, "test/dummy/app/views/patients/_row.html.erb", 1],
                  ["new_patient", nil, false, "test/dummy/app/views/patients/_row.html.erb", 2]], links(p)
  end

  def test_non_route_stem_dropped_without_warning
    assert page("PatientsController", "index")["links"].none? { |l| l["stem"] == "image" }
    assert result["warnings"].none? { |w| w["message"].include?("image") }
  end

  def test_form_flag
    p = page("PatientsController", "new")
    assert_equal [["patients", nil, true, "test/dummy/app/views/patients/new.html.erb", 1]], links(p)
    assert_nil p["links"].first["method"]
  end

  def test_redirect
    p = page("PatientsController", "create")
    assert_nil p["template"]
    assert_equal [["patient", nil]], p["redirects"].map { |r| [r["stem"], r["engine"]] }
    assert_equal "PatientsController#create", p["redirects"].first["source"]["name"]
    assert_equal "test/dummy/app/controllers/patients_controller.rb", p["redirects"].first["source"]["path"]
  end

  def test_layout_links_live_on_the_layout_only
    layout = result["layouts"].find { |l| l["name"] == "application" }
    assert_equal "test/dummy/app/views/layouts/application.html.erb", layout["source"]["path"]
    assert_includes layout["controllers"], "PatientsController"
    assert_equal ["patients"], layout["links"].map { |l| l["stem"] }
    assert result["pages"].none? { |p| p["links"].any? { |l| l["source"]["path"].include?("layouts/") } }
  end

  def test_unparseable_partial_warns
    w = result["warnings"].find { |x| x["message"].include?("patients/_broken.html.erb") }
    assert_equal "pages", w["where"]
    assert_match(/\(line \d+\)/, w["message"])
  end

  def test_engine_template_links_join_on_engine
    p = page("Blog::PostsController", "index")
    assert_equal "test/dummy/engines/blog/app/views/blog/posts/index.html.erb", p["template"]["path"]
    assert_equal [["posts", "Blog::Engine"], ["patients", nil]], p["links"].map { |l| [l["stem"], l["engine"]] }
  end

  def test_inertia_page_has_node_and_one_warning
    p = page("PatientsController", "show")
    assert_equal "test/dummy/app/frontend/pages/Patients/Show.tsx", p["template"]["path"]
    assert_nil p["format"]
    assert_equal [], p["links"]
    assert_equal 1, result["warnings"].count { |w| w["message"].include?("Inertia") }
  end

  def test_actions_without_template_links_or_redirects_have_no_row
    assert_nil page("AdminController", "index")
  end

  def test_rows_sorted
    keys = result["pages"].map { |p| [p["controller"], p["action"]] }
    assert_equal keys.sort, keys
  end

  def test_partial_cycle_terminates_and_lists_each_once
    names = page("PatientsController", "new")["partials"].map { |n| File.basename(n["path"]) }.sort
    assert_equal %w[_broken.html.erb _loop_a.html.erb _loop_b.html.erb], names
  end

  # An engine's dummy app sits inside the engine's root (Spina: test/dummy under the repository), so the app root competes.
  def test_engine_of_prefers_the_longest_root
    candidates = [[nil, "/r/test/dummy"], ["Spina::Engine", "/r"]]
    assert_nil RailsVis::Collectors::Pages.engine_of("/r/test/dummy/app/views/layouts/application.html.erb", candidates)
    assert_equal "Spina::Engine", RailsVis::Collectors::Pages.engine_of("/r/app/views/spina/admin/pages/index.html.erb", candidates)
    assert_nil RailsVis::Collectors::Pages.engine_of("/elsewhere/x.erb", candidates)
  end
end
