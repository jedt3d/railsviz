require "test_helper"

class RailsVisTest < Minitest::Test
  def test_version_and_dummy_boot
    assert_equal "0.1.0", RailsVis::VERSION
    assert Rails.application.initialized?
    assert_equal "dummy", RailsVis.root.basename.to_s
  end

  # test_helper does not assign it; the Railtie initializer does at boot.
  def test_railtie_sets_root
    assert_equal Rails.root, RailsVis.root
  end
end
