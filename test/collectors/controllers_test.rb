# frozen_string_literal: true

require "test_helper"

class ControllersCollectorTest < Minitest::Test
  def result
    @result ||= begin
      repo = RailsVis::Repo.detect(RailsVis.root)
      routes = RailsVis::Collectors::Routes.new(repo: repo).call["routes"]
      config = RailsVis::Config.load(RailsVis.root)
      RailsVis::Collectors::Controllers.new(repo: repo, config: config, routes: routes, model_names: ["Patient"]).call
    end
  end

  def patients = result["controllers"].find { |c| c["name"] == "PatientsController" }
  def action(name) = patients["actions"].find { |a| a["name"] == name }
  def controller_path = "test/dummy/app/controllers/patients_controller.rb"

  def test_actions_and_sources
    assert_equal %w[create export index new show], patients["actions"].map { |a| a["name"] }.sort
    assert_equal "ApplicationController", patients["parent"]
    assert_equal controller_path, patients["source"]["path"]
    def_line = File.readlines(RailsVis.root.join("app/controllers/patients_controller.rb")).index { |l| l.include?("def show") } + 1
    assert_equal controller_path, action("show")["source"]["path"]
    assert_equal def_line, action("show")["source"]["line"]
  end

  def test_filters
    assert_equal [%w[before load_patient]], patients["filters"].map { |f| [f["kind"], f["name"]] }
    filter = patients["filters"].first
    assert_equal ["show"], filter["only"]
    assert_nil filter["except"]
    assert_equal controller_path, filter["source"]["path"]
    assert_equal decl_line("patients_controller.rb", "before_action :load_patient, only: %i[show]"), filter["source"]["line"]
    assert_equal "PatientsController before_action :load_patient", filter["source"]["name"]
    assert filter["doc_url"].end_with?("#method-i-before_action")
  end

  def admin = result["controllers"].find { |c| c["name"] == "AdminController" }
  def decl_line(file, text) = File.readlines(RailsVis.root.join("app/controllers", file)).index { |l| l.include?(text) } + 1

  def test_filter_links_to_declaration_even_when_method_is_not_app_code
    filter = admin["filters"].find { |f| f["name"] == "authenticate_user!" }
    assert_equal "test/dummy/app/controllers/admin_controller.rb", filter["source"]["path"]
    assert_equal decl_line("admin_controller.rb", "before_action :authenticate_user!"), filter["source"]["line"]
    assert_equal "AdminController before_action :authenticate_user!", filter["source"]["name"]
    assert_equal filter["source"]["line"], admin["filters"].find { |f| f["name"] == "set_locale" }["source"]["line"]
  end

  def test_inherited_and_concern_filters_link_to_their_declaring_file
    reports = result["controllers"].find { |c| c["name"] == "Admin::ReportsController" }
    auth = reports["filters"].find { |f| f["name"] == "authenticate_user!" }
    assert_equal "test/dummy/app/controllers/admin_controller.rb", auth["source"]["path"]
    audit = reports["filters"].find { |f| f["name"] == "audit" }
    assert_equal "after", audit["kind"]
    assert_equal "test/dummy/app/controllers/concerns/audited.rb", audit["source"]["path"]
    assert_equal decl_line("concerns/audited.rb", "after_action :audit"), audit["source"]["line"]
    assert_equal "Audited after_action :audit", audit["source"]["name"]
  end

  def test_framework_filters_dropped
    application = result["controllers"].find { |c| c["name"] == "ApplicationController" }
    assert_equal [], application["filters"]
  end

  def test_failing_action_warns_and_keeps_controller
    broken = result["controllers"].find { |c| c["name"] == "BrokenController" }
    assert_equal %w[ghost index], broken["actions"].map { |a| a["name"] }.sort
    ghost = broken["actions"].find { |a| a["name"] == "ghost" }
    assert_equal({ "name" => "ghost", "source" => nil, "models" => [], "view" => nil }, ghost)
    assert result["warnings"].any? { |w| w["message"].start_with?("BrokenController#ghost: NameError") }
  end

  def test_models_referenced
    assert_equal [], action("show")["models"]
    assert_equal ["Patient"], action("index")["models"]
  end

  def test_view_template
    assert_equal({ "kind" => "template", "path" => "test/dummy/app/views/patients/index.html.erb" }, action("index")["view"].slice("kind", "path"))
  end

  def test_view_inertia
    assert_equal({ "kind" => "inertia", "path" => "test/dummy/app/frontend/pages/Patients/Show.tsx" }, action("show")["view"].slice("kind", "path"))
  end

  def test_view_dynamic_inertia_warns
    assert_nil action("export")["view"]
    assert result["warnings"].any? { |w| w["message"].include?("PatientsController#export") }
  end

  def test_engine_controller_view_resolves_through_view_paths
    posts = result["controllers"].find { |c| c["name"] == "Blog::PostsController" }
    assert_equal "test/dummy/engines/blog/app/views/blog/posts/index.html.erb", posts["actions"].first["view"]["path"]
  end

  def test_missing_controller_warns
    assert result["warnings"].any? { |w| w["message"].include?("health#show") }
    assert result["controllers"].none? { |c| c["name"] == "HealthController" }
  end

  def test_gem_controllers_excluded
    assert result["controllers"].all? { |c| c["source"]["path"].start_with?("test/dummy/") }
  end
end
