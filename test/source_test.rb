# frozen_string_literal: true

require "test_helper"

class SourceTest < Minitest::Test
  def repo = RailsVis::Repo.detect(RailsVis.root)

  def test_for_method_points_at_definition_line
    node = RailsVis::Source.for_method(PatientsController.instance_method(:show), repo: repo)
    assert_equal %w[name path line url], node.keys
    assert_equal "PatientsController#show", node["name"]
    assert_equal "test/dummy/app/controllers/patients_controller.rb", node["path"]
    assert_equal 4, node["line"]
  end

  def test_for_const
    node = RailsVis::Source.for_const(PatientsController, repo: repo)
    assert_equal "PatientsController", node["name"]
    assert_equal 1, node["line"]
  end

  def test_app_code
    assert RailsVis::Source.app_code?(RailsVis.root.join("app/controllers/patients_controller.rb").to_s, repo: repo)
    refute RailsVis::Source.app_code?(ActionController::Base.instance_method(:render).source_location.first, repo: repo)
  end
end
