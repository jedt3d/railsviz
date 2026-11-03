# frozen_string_literal: true

require "test_helper"

class GemsCollectorTest < Minitest::Test
  def result
    @result ||= begin
      repo = RailsVis::Repo.detect(RailsVis.root)
      middleware = RailsVis::Collectors::Middleware.new(repo: repo).call["middleware"]
      initializers = [{ "railtie" => "ActiveRecord::Railtie", "count" => 27 }, { "railtie" => "ActionController::Railtie", "count" => 11 }]
      RailsVis::Collectors::Gems.new(repo: repo, middleware: middleware, initializers: initializers).call
    end
  end
  def gems = result["gems"]
  def find(name) = gems.find { |g| g["name"] == name }

  def test_every_bundled_gem_listed_direct_first
    assert_equal Bundler.load.specs.size, gems.size
    direct = (Bundler.definition.dependencies.map(&:name) & Bundler.load.specs.map(&:name)).sort
    assert_equal direct, gems.take(direct.size).map { |g| g["name"] }
    assert gems.drop(direct.size).none? { |g| g["direct"] }
  end

  def test_railtie_initializers_and_middleware
    ar = find("activerecord")
    assert_equal "ActiveRecord::Railtie", ar["railtie"]
    assert_equal 27, ar["initializers"]
    ap = find("actionpack")
    assert_includes ap["middleware"], "ActionDispatch::Static"
    assert_equal Gem.loaded_specs["actionpack"].version.to_s, ap["version"]
    assert_equal "https://rubygems.org/gems/rake/versions/#{Gem.loaded_specs["rake"].version}", find("rake")["links"]["rubygems"]
  end

  def test_gem_without_railtie
    rake = find("rake")
    assert_nil rake["railtie"]
    assert_equal 0, rake["initializers"]
    assert_equal [], rake["middleware"]
  end
end
