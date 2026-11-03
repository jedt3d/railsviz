# frozen_string_literal: true

module RailsVis
  module Collectors
    # Lists application routes with the routes-file line that drew each one; mounted engines are expanded in place.
    class Routes
      def initialize(repo:)
        @repo = repo
      end

      def call
        @warnings = []
        ActionDispatch::Routing::Mapper.route_source_locations = true
        Rails.application.reload_routes!
        { "routes" => collect(Rails.application.routes.routes, prefix: "", engine: nil), "warnings" => @warnings }
      end

      private

      def collect(routes, prefix:, engine:)
        routes.flat_map do |route|
          path = prefix.chomp("/") + route.path.spec.to_s.delete_suffix("(.:format)")
          # route.internal covers /cable etc.; framework engines (Active Storage, Action Mailbox) draw /rails/... without the flag.
          next [] if route.internal || path.start_with?("/rails/")
          app = route.app
          app = app.app if app.is_a?(ActionDispatch::Routing::Mapper::Constraints)
          next collect(app.routes.routes, prefix: path, engine: app.name) if app.is_a?(Class) && app < Rails::Engine
          [row(route, path, engine)]
        rescue StandardError => e
          add_warning("#{path || route.inspect}: #{e.class}: #{e.message}")
          []
        end
      end

      def row(route, path, engine)
        {
          "verb" => route.verb.to_s,
          "path" => path,
          "name" => route.name,
          "controller" => route.defaults[:controller],
          "action" => route.defaults[:action],
          "engine" => engine,
          "source" => source(route, path),
          "doc_url" => DocLinks.routing
        }
      end

      def source(route, path)
        file, _, line = route.source_location.to_s.rpartition(":")
        # Gem routes come back backtrace-cleaned ("actionmailbox (8.1.4) config/routes.rb:5"), not a real file path.
        return Source.node(name: path, path: file, line: line.to_i, repo: @repo) if File.absolute_path?(file)
        add_warning("#{route.verb} #{path}: no source location (drawn outside a reloadable routes file, or by a gem)")
        nil
      end

      def add_warning(message)
        @warnings << { "where" => "routes", "message" => message }
      end
    end
  end
end
