# frozen_string_literal: true

require "test_helper"

class ModelsCollectorTest < Minitest::Test
  def result
    @result ||= RailsVis::Collectors::Models.new(repo: RailsVis::Repo.detect(RailsVis.root)).call
  end

  def patient = result["models"].find { |m| m["name"] == "Patient" }

  def test_models_listed
    names = result["models"].map { |m| m["name"] }
    assert_includes names, "Patient"
    assert_includes names, "Visit"
    refute_includes names, "Pending"
    refute_includes names, "ApplicationRecord"
    assert_equal names, result["model_names"]
    assert_equal "test/dummy/app/models/patient.rb", patient["source"]["path"]
    assert_equal "patients", patient["table"]
  end

  def test_pending_warns
    assert(result["warnings"].any? { |w| w["where"] == "models" && w["message"].include?("Pending") && w["message"].include?("table") })
  end

  def test_associations
    visits = patient["associations"].find { |a| a["name"] == "visits" }
    assert_equal({ "macro" => "has_many", "name" => "visits", "class_name" => "Visit", "dependent" => "destroy" },
                 visits.slice("macro", "name", "class_name", "dependent"))
    assert_equal "patient_id", visits["foreign_key"]
    assert_nil visits["through"]
    assert visits["doc_url"].end_with?("#method-i-has_many")
  end

  def test_validations
    presence = patient["validations"].find { |v| v["kind"] == "presence" }
    assert_equal ["name"], presence["attributes"]
    assert_equal({}, presence["options"])
    assert presence["doc_url"].end_with?("#method-i-validates_presence_of")
  end

  def test_callbacks
    assert_equal [%w[save before normalize_name]], patient["callbacks"].map { |c| c.values_at("event", "kind", "name") }
    source = patient["callbacks"].first["source"]
    def_line = File.readlines(RailsVis.root.join("app/models/patient.rb")).index { |l| l.include?("def normalize_name") } + 1
    assert_equal "test/dummy/app/models/patient.rb", source["path"]
    assert_equal def_line, source["line"]
  end

  def test_columns_and_indexes
    name = patient["columns"].find { |c| c["name"] == "name" }
    assert_equal({ "name" => "name", "type" => "string", "null" => false, "default" => nil }, name)
    assert_equal [{ "name" => "index_patients_on_name", "columns" => ["name"], "unique" => false }], patient["indexes"]
  end

  def test_database_role
    assert_equal "primary", patient["database"]
  end
end
