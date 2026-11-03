# frozen_string_literal: true

require "test_helper"

class DatabasesCollectorTest < Minitest::Test
  def result
    @result ||= begin
      models = RailsVis::Collectors::Models.new(repo: RailsVis::Repo.detect(RailsVis.root)).call["models"]
      RailsVis::Collectors::Databases.new(models: models).call
    end
  end

  def entry(env, name) = result["databases"].find { |d| d["env"] == env && d["name"] == name }

  def test_all_envs_listed
    pairs = result["databases"].map { |d| [d["env"], d["name"]] }
    assert_includes pairs, %w[test primary]
    assert_includes pairs, %w[production cache]
    assert_includes pairs, %w[production queue]
    refute(result["databases"].any? { |d| d["env"] == "default" })
    assert_equal false, entry("test", "primary")["replica"]
  end

  def test_solid_mapping
    cache = entry("production", "cache")
    if Gem.loaded_specs["solid_cache"]
      assert_equal "solid_cache", cache["solid_component"]
    else
      assert_nil cache["solid_component"]
    end
    assert_equal "db/cache_migrate", cache["migrations_paths"]
  end

  def test_replica
    replica = entry("production", "replica")
    assert_equal true, replica["replica"]
    assert_nil replica["solid_component"]
  end

  def test_models_attached
    assert_includes entry("test", "primary")["models"], "Patient"
  end

  def test_no_secret_keys
    result["databases"].each do |d|
      assert_empty d.keys & %w[url host username password], d.inspect
    end
  end
end
