# frozen_string_literal: true

module RailsVis
  # Builds the four-key code node ("name", "path", "line", "url") used everywhere in the graph.
  module Source
    module_function

    def node(name:, path:, line:, repo:)
      { "name" => name, "path" => repo.relative(path), "line" => line, "url" => repo.url_for(path, line) }
    end

    def app_code?(path, repo:)
      return false if gem_code?(path)
      !repo.relative(path).start_with?("..")
    end

    # Gem code, even when a vendored bundle (vendor/bundle) sits inside the repo root.
    def gem_code?(path)
      real = begin
        File.realpath(path.to_s)
      rescue SystemCallError
        File.expand_path(path.to_s)
      end
      gem_roots.any? { |root| real.start_with?(root + File::SEPARATOR) }
    end

    # Cached per distinct Gem.path/bundle_path, so it is computed once in normal use.
    def gem_roots
      dirs = Gem.path + (defined?(Bundler) ? [Bundler.bundle_path.to_s] : [])
      (@gem_roots ||= {})[dirs] ||= dirs.filter_map do |d|
        File.realpath(d) if File.directory?(d)
      end
    end

    def for_method(method, repo:)
      path, line = method.source_location
      return unless path
      owner = method.owner
      name = owner.singleton_class? ? "#{owner.attached_object.name}.#{method.name}" : "#{owner.name}##{method.name}"
      node(name: name, path: path, line: line, repo: repo)
    end

    def for_const(klass, repo:)
      path, line = Object.const_source_location(klass.name)
      node(name: klass.name, path: path, line: line, repo: repo) if path
    end
  end
end
