# frozen_string_literal: true

require "test_helper"

class BodyScanTest < Minitest::Test
  def scan(name)
    path, line = PatientsController.instance_method(name).source_location
    RailsVis::BodyScan.new(path, name, line)
  end

  def test_constants_in_load_patient = assert_equal(["Patient"], scan(:load_patient).constants)
  def test_inertia_literal = assert_equal("Patients/Show", scan(:show).inertia_component)
  def test_inertia_dynamic = assert_equal(:dynamic, scan(:export).inertia_component)
  def test_no_inertia = assert_nil(scan(:index).inertia_component)
end
