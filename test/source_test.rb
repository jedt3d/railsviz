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
    refute RailsVis::Source.app_code?(File.join(RbConfig::CONFIG["rubylibdir"], "set.rb"), repo: repo)
  end

  def test_gems_vendored_inside_repo_are_not_app_code
    probe = RailsVis.root.join("tmp/vendor_probe")
    file = probe.join("gems/fake-1.0/lib/fake.rb")
    FileUtils.mkdir_p(file.dirname)
    File.write(file, "")
    original = Gem.path
    Gem.paths = { "GEM_PATH" => ([probe.to_s] + original).join(File::PATH_SEPARATOR), "GEM_HOME" => Gem.dir }
    refute RailsVis::Source.app_code?(file.to_s, repo: repo)
    assert RailsVis::Source.app_code?(RailsVis.root.join("test/dummy/app/models/patient.rb").to_s, repo: repo)
  ensure
    Gem.paths = { "GEM_PATH" => original.join(File::PATH_SEPARATOR), "GEM_HOME" => Gem.dir } if original
    FileUtils.rm_rf(probe)
  end
end
