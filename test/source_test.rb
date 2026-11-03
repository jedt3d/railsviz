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
    assert RailsVis::Source.app_code?(RailsVis.root.join("app/models/patient.rb").to_s, repo: repo)
  ensure
    Gem.paths = { "GEM_PATH" => original.join(File::PATH_SEPARATOR), "GEM_HOME" => Gem.dir } if original
    FileUtils.rm_rf(probe)
  end

  def test_repo_relative_paths_resolve_from_any_working_directory
    probe = RailsVis.root.join("tmp/vendor_probe")
    file = probe.join("gems/fake-1.0/lib/fake.rb")
    FileUtils.mkdir_p(file.dirname)
    File.write(file, "")
    original = Gem.path
    Gem.paths = { "GEM_PATH" => ([probe.to_s] + original).join(File::PATH_SEPARATOR), "GEM_HOME" => Gem.dir }
    rel_gem = repo.relative(file)
    rel_app = repo.relative(RailsVis.root.join("app/models/patient.rb"))
    Dir.chdir(RailsVis.root) do
      refute RailsVis::Source.app_code?(rel_gem, repo: repo)
      assert RailsVis::Source.app_code?(rel_app, repo: repo)
    end
  ensure
    Gem.paths = { "GEM_PATH" => original.join(File::PATH_SEPARATOR), "GEM_HOME" => Gem.dir } if original
    FileUtils.rm_rf(probe)
  end
  # Gem code has no repo path; the node links to the gem instead.
  def test_gem_code_node_links_to_gem
    require "rails/info_controller"
    node = RailsVis::Source.for_method(Rails::InfoController.instance_method(:properties), repo: repo)
    assert_nil node["path"]
    assert_nil node["line"]
    assert_kind_of String, node["url"]
    assert node["url"].start_with?("https://"), node["url"]
  end

  def test_gem_spec
    repo = RailsVis::Repo.detect(RailsVis.root)
    assert_equal "rack", RailsVis::Source.gem_spec(Object.const_source_location("Rack::Sendfile").first, repo: repo).name
    assert_nil RailsVis::Source.gem_spec(RailsVis.root.join("config/application.rb").to_s, repo: repo)
  end
end
