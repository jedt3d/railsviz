# frozen_string_literal: true

module RailsVis
  module Collectors
    # The Rack middleware stack in order, each entry with the gem that defines it. Arguments are never written.
    class Middleware
      def initialize(repo:, stack: Rails.application.middleware)
        @repo = repo
        @stack = stack
      end

      def call
        warnings = []
        rows = @stack.map do |entry|
          # entry.name calls klass.name, which a Proc or a plain object lacks; inspect gives its class name instead.
          label = entry.klass.respond_to?(:name) ? entry.name : entry.inspect
          row(entry, label)
        rescue StandardError => e
          warnings << Collectors.error("middleware", label, e)
          { "name" => label, "gem" => nil, "source" => nil, "doc_url" => DocLinks.rails_on_rack }
        end
        { "middleware" => rows, "warnings" => warnings }
      end

      private

      def row(entry, label)
        # An entry inserted as an object (ActiveSupport's LocalCache middleware instance) resolves through its class.
        klass = entry.klass.is_a?(Module) ? entry.klass : entry.klass.class
        path, line = Object.const_source_location(klass.name) if klass.name
        spec = Source.gem_spec(path, repo: @repo)
        {
          "name" => label,
          "gem" => spec && { "name" => spec.name, "version" => spec.version.to_s },
          "source" => path && Source.node(name: klass.name, path: path, line: line, repo: @repo),
          "doc_url" => DocLinks.rails_on_rack
        }
      end
    end
  end
end
