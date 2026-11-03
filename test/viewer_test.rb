# frozen_string_literal: true

require "minitest/autorun"
require "rbconfig"

class ViewerTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  VIEWER = File.join(ROOT, "viewer/index.html")
  BUILD = File.join(ROOT, "script/build_viewer.rb")

  def test_built_viewer_is_self_contained
    html = File.read(VIEWER, encoding: "UTF-8")
    assert_equal 1, html.scan("<!--RAILS_VIS_DATA-->").size
    refute_includes html, 'src="http'
    refute_match(/<link[^>]*href="http/, html)
    assert_includes html, "marked"
    assert_includes html, "mermaid"
  end

  def test_build_is_idempotent
    run_build
    first = File.binread(VIEWER)
    run_build
    assert_equal first, File.binread(VIEWER)
  end

  private

  def run_build
    assert system(RbConfig.ruby, BUILD, out: File::NULL), "build failed"
  end
end
