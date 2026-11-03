# frozen_string_literal: true

module RailsVis
  # Builds the four-key code node ("name", "path", "line", "url") used everywhere in the graph.
  module Source
    module_function

    # Gem code has no repository path; it links to the gem (source, homepage or rubygems.org) instead.
    def node(name:, path:, line:, repo:)
      return { "name" => name, "path" => nil, "line" => nil, "url" => gem_url(path, repo: repo) } if gem_code?(path, repo: repo)
      { "name" => name, "path" => repo.relative(path), "line" => line, "url" => repo.url_for(path, line) }
    end

    def app_code?(path, repo:)
      return false if path.nil? # a gem-code node carries no path
      return false if gem_code?(path, repo: repo)
      !repo.relative(path).start_with?("..")
    end

    # Gem code, even when a vendored bundle (vendor/bundle) sits inside the repo root.
    def gem_code?(path, repo:)
      real = real_path(path, repo)
      gem_roots.any? { |root| real.start_with?(root + File::SEPARATOR) }
    end

    def gem_url(path, repo:)
      real = real_path(path, repo)
      spec = Gem.loaded_specs.values.find { |s| real.start_with?(real_path(s.full_gem_path, repo) + File::SEPARATOR) }
      return unless spec
      links = DocLinks.gem(spec.name)
      links[:source_code_uri] || links[:homepage] || links[:rubygems]
    end

    def real_path(path, repo)
      abs = File.expand_path(path.to_s, repo.root.to_s)
      File.realpath(abs)
    rescue SystemCallError
      abs
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
