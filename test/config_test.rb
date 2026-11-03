# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class ConfigTest < Minitest::Test
  def test_defaults_when_file_absent
    Dir.mktmpdir do |dir|
      c = RailsVis::Config.load(dir)
      assert_equal ["docs/**/*.md"], c.docs
      assert_equal ["docs/superpowers/**"], c.exclude
      assert_equal [], c.start_here
      assert_equal "app/frontend/pages", c.pages_dir
      assert_nil c.repo_url
    end
  end

  def test_reads_yaml
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p("#{dir}/config")
      File.write("#{dir}/config/rails_vis.yml", "pages_dir: app/pages\nstart_here: [docs/a.md]\n")
      c = RailsVis::Config.load(dir)
      assert_equal "app/pages", c.pages_dir
      assert_equal ["docs/a.md"], c.start_here
      assert_equal ["docs/**/*.md"], c.docs
    end
  end
end
