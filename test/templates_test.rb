# frozen_string_literal: true

require "test_helper"

class TemplatesTest < Minitest::Test
  def test_find_html_template_through_view_paths
    t = RailsVis::Templates.find(PatientsController, "index")
    assert_equal RailsVis.root.join("app/views/patients/index.html.erb").to_s, t.identifier
    assert_equal "patients/index", t.virtual_path
    assert_equal :html, t.format
  end

  def test_find_engine_template
    t = RailsVis::Templates.find(Blog::PostsController, "index")
    assert t.identifier.end_with?("engines/blog/app/views/blog/posts/index.html.erb")
  end

  def test_find_missing_is_nil
    assert_nil RailsVis::Templates.find(PatientsController, "nothing")
  end

  # A bare name falls back from the template's own folder to the controller's view prefixes, as Rails does.
  def test_bare_partial_resolves_through_controller_prefixes
    t = RailsVis::Templates.partial(PatientsController, "header", "layouts/application")
    assert_equal RailsVis.root.join("app/views/application/_header.html.erb").to_s, t.identifier
  end

  def test_missing_partial_is_nil
    assert_nil RailsVis::Templates.partial(PatientsController, "nothing", "patients/index")
  end

  def test_layout
    t = RailsVis::Templates.layout(PatientsController)
    assert_equal "layouts/application", t.virtual_path
    assert_equal "application", RailsVis::Templates.layout_name(t)
  end

  def test_compile_wraps_in_a_method_and_keeps_lines
    t = RailsVis::Templates.layout(PatientsController)
    code = RailsVis::Templates.compile(t)
    assert code.start_with?("def _rails_vis_template; ")
    result = Prism.parse(code)
    assert_equal [], result.errors.map(&:message)
    lines = File.readlines(t.identifier)
    call = find_call(result.value, :csrf_meta_tags)
    assert_equal lines.index { |l| l.include?("csrf_meta_tags") } + 1, call.location.start_line
    refute_includes code, "<!-- BEGIN"
  end

  def test_compile_unknown_handler_raises
    t = RailsVis::Templates.find(PatientsController, "index")
    fake = t.dup
    fake.define_singleton_method(:identifier) { "/nowhere/x.html.unknownlang" }
    assert_raises(RailsVis::Error) { RailsVis::Templates.compile(fake) }
  end

  private

  def find_call(node, name)
    return node if node.is_a?(Prism::CallNode) && node.name == name
    node.compact_child_nodes.each { |c| (f = find_call(c, name)) and return f }
    nil
  end
end
