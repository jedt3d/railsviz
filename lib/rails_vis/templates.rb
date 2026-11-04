# frozen_string_literal: true

module RailsVis
  # Resolves and compiles view templates the way Rails does: through a controller's own view paths,
  # so engine and gem templates are found as well as the app's.
  module Templates
    module_function

    # Through the controller's view prefixes (its own path, then its ancestors'), as Rails renders an action.
    def find(klass, action)
      lookup(klass, html: true).find_all(action, klass._prefixes, false).first ||
        lookup(klass, html: false).find_all(action, klass._prefixes, false).first
    end

    def layout(klass)
      lc = lookup(klass, html: true)
      name = klass.new.send(:_layout, lc, [:html], [])
      return name if name.is_a?(ActionView::Template)
      name.is_a?(String) ? lc.find_all(name, ["layouts"], false).first : nil
    end

    def layout_name(template)
      template.virtual_path.delete_prefix("layouts/")
    end

    # name: "shared/form" (that directory) or "form" (the rendering template's directory, then the controller's
    # view prefixes, as Rails does).
    def partial(klass, name, from_virtual_path)
      dirs, base = if name.include?("/") then [[File.dirname(name)], File.basename(name)]
                   else [[File.dirname(from_virtual_path), *klass._prefixes].uniq, name]
                   end
      lookup(klass, html: true).find_all(base, dirs, true).first ||
        lookup(klass, html: false).find_all(base, dirs, true).first
    end

    # Ruby source of the template wrapped in a method; line numbers match the template's own.
    def compile(template)
      compile_file(template.identifier, format: template.format)
    end

    # Same as compile for a file found outside a lookup (a view component's sidecar template).
    def compile_file(path, format: :html)
      ext = File.extname(path).delete_prefix(".").to_sym
      handler = ActionView::Template.registered_template_handler(ext)
      raise RailsVis::Error, "no template handler for .#{ext}" unless handler
      source = File.read(path, encoding: "UTF-8")
      t = ActionView::Template.new(source, path, handler, locals: [], format: format)
      annotate = ActionView::Base.annotate_rendered_view_with_filenames
      ActionView::Base.annotate_rendered_view_with_filenames = false # the BEGIN comment would shift lines by one
      "def _rails_vis_template; " + handler.call(t, source) + "\nend"
    ensure
      ActionView::Base.annotate_rendered_view_with_filenames = annotate unless annotate.nil?
    end

    def lookup(klass, html:)
      ActionView::LookupContext.new(klass._view_paths, html ? { formats: [:html] } : {})
    end
    private_class_method :lookup
  end
end
