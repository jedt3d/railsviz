# frozen_string_literal: true

require "test_helper"

class CollectorsErrorTest < Minitest::Test
  def test_quiet_error_matched_by_class_name
    klass = Class.new(StandardError) { def self.name = "PG::Error" }
    w = RailsVis::Collectors.error("models", "Patient", klass.new("host: db.internal user: admin"))
    assert_equal "Patient: PG::Error", w["message"]
  end

  def test_other_error_keeps_first_message_line
    w = RailsVis::Collectors.error("models", "Patient", RuntimeError.new("boom"))
    assert_equal "Patient: RuntimeError: boom", w["message"]
  end

  # Constantizing "SQLite3::Exception" requires the sqlite3 gem, which raises LoadError on hosts without it.
  def test_never_constantizes
    refute_match(/constantize/, File.read(File.expand_path("../lib/rails_vis/collectors.rb", __dir__)))
  end
end
