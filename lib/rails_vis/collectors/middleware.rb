# frozen_string_literal: true

module RailsVis
  module Collectors
    # The Rack middleware stack in order, each entry with the gem that defines it. Arguments are never written.
    class Middleware
      def initialize(repo:)
        @repo = repo
      end

      def call
        warnings = []
        rows = Rails.application.middleware.map do |entry|
          row(entry)
        rescue StandardError => e
          warnings << Collectors.error("middleware", entry.name, e)
          { "name" => entry.name, "gem" => nil, "source" => nil, "doc_url" => DocLinks.rails_on_rack }
        end
        { "middleware" => rows, "warnings" => warnings }
      end

      private

      def row(entry)
        # An entry inserted as an object (ActiveSupport's LocalCache middleware instance) resolves through its class.
        klass = entry.klass.is_a?(Module) ? entry.klass : entry.klass.class
        path, line = Object.const_source_location(klass.name) if klass.name
        spec = Source.gem_spec(path, repo: @repo)
        {
          "name" => entry.name,
          "gem" => spec && { "name" => spec.name, "version" => spec.version.to_s },
          "source" => path && Source.node(name: klass.name, path: path, line: line, repo: @repo),
          "doc_url" => DocLinks.rails_on_rack
        }
      end
    end
  end
end
