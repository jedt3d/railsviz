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
    assert_equal %w[export index show], patients["actions"].map { |a| a["name"] }.sort
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
    assert_equal "PatientsController#load_patient", filter["source"]["name"]
    assert filter["doc_url"].end_with?("#method-i-before_action")
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

  def test_missing_controller_warns
    assert result["warnings"].any? { |w| w["message"].include?("health#show") }
    assert result["warnings"].any? { |w| w["message"].include?("blog/posts#index") }
    assert result["controllers"].none? { |c| c["name"] == "HealthController" }
  end

  def test_gem_controllers_excluded
    assert result["controllers"].all? { |c| c["source"]["path"].start_with?("test/dummy/") }
  end
end
