# frozen_string_literal: true

require "test_helper"

class ViewScanTest < Minitest::Test
  def scan(src) = RailsVis::ViewScan.new(src, path: "x.rb")

  def test_helpers_with_receivers
    s = scan("link_to 'a', patients_path\nlink_to 'b', main_app.root_path\nlink_to 'c', spina.admin_pages_path\nlink_to 'd', @x.bar_path\nimage_path('x')")
    assert_equal [["patients", nil, 1], ["root", "main_app", 2], ["admin_pages", "spina", 3], ["bar", :other, 4], ["image", nil, 5]],
                 s.helpers.map { |h| [h["stem"], h["receiver"], h["line"]] }
    assert_equal "patients_path", s.helpers.first["name"]
  end

  def test_form_detection
    src = <<~RUBY
      form_with url: patients_path do |f| end
      button_to 'x', patient_path(1)
      link_to 'del', patient_path(1), method: :delete
      link_to 'del2', patient_path(1), data: { turbo_method: :delete }
      link_to 'frame', patient_path(1), data: { turbo_frame: 'x' }
      form_tag(patients_path)
      form_for(@p, url: patients_path) {}
    RUBY
    s = scan(src)
    assert_equal [true, true, true, true, false, true, true], s.helpers.map { |h| h["form"] }
    assert_equal [nil, nil, "delete", "delete", nil, nil, nil], s.helpers.map { |h| h["method"] }
  end

  def test_redirect_and_def
    s = scan("class C\n  def create\n    redirect_to patient_path(1)\n  end\n  def show\n    x = patients_path\n  end\nend")
    assert_equal [["patient", true, "create"], ["patients", false, "show"]], s.helpers.map { |h| [h["stem"], h["redirect"], h["def"]] }
  end

  def test_template_wrapper_def_is_nil
    assert_nil scan("def _rails_vis_template\n  patients_path\nend").helpers.first["def"]
  end

  def test_partials_and_components
    s = scan("render 'row'\nrender partial: 'shared/header'\nrender 'dir/x', locals: {}\nrender x\nrender Spina::TabComponent.new(a: 1)\nrender(Other.new)")
    assert_equal ["row", "shared/header", "dir/x"], s.partials
    assert_equal ["Spina::TabComponent", "Other"], s.components
  end

  def test_parse_error_is_reported_not_raised
    s = scan("if\n")
    assert_match(/\Ax\.rb: .+\(line \d+\)\z/, s.error)
    assert_equal [], s.helpers
  end

  def test_clean_source_has_no_error
    assert_nil scan("patients_path").error
  end
end
