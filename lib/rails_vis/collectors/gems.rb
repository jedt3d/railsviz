# frozen_string_literal: true

module RailsVis
  module Collectors
    # Every bundled gem: version, whether the Gemfile names it, its Railtie and what it injects into the app.
    class Gems
      def initialize(repo:, middleware:, initializers:)
        @repo = repo
        @middleware = middleware
        @initializers = initializers
      end

      def call
        warnings = []
        direct = Bundler.definition.dependencies.map(&:name)
        railties = railtie_gems
        @initializer_gems = @initializers.to_h { |i| [i["railtie"], gem_of(i["railtie"])] }
        specs = Bundler.load.specs.sort_by { |s| [direct.include?(s.name) ? 0 : 1, s.name] }
        gems = specs.filter_map do |spec|
          row(spec, direct.include?(spec.name), railties)
        rescue StandardError => e
          warnings << Collectors.error("gems", spec.name, e)
          nil
        end
        { "gems" => gems, "warnings" => warnings }
      end

      private

      def row(spec, direct, railties)
        {
          "name" => spec.name,
          "version" => spec.version.to_s,
          "direct" => direct,
          "railtie" => railties.find { |_, gem| gem == spec.name }&.first,
          "initializers" => @initializers.sum { |i| @initializer_gems[i["railtie"]] == spec.name ? i["count"].to_i : 0 },
          "middleware" => @middleware.filter_map { |m| m["name"] if m.dig("gem", "name") == spec.name },
          "links" => DocLinks.gem(spec.name).transform_keys(&:to_s)
        }
      end

      # Railtie name => gem name, in name order, so the first match per gem wins.
      def railtie_gems
        Rails::Railtie.descendants.filter_map(&:name).sort.to_h { |name| [name, gem_of(name)] }
      end

      def gem_of(const_name)
        path = Object.const_source_location(const_name.to_s)&.first
        Source.gem_spec(path, repo: @repo)&.name
      rescue NameError
        nil
      end
    end
  end
end
