# frozen_string_literal: true

module RailsVis
  module Collectors
    # Lists every database config across all environments. Reads only non-secret attributes.
    class Databases
      SOLID = { "cache" => "solid_cache", "queue" => "solid_queue", "cable" => "solid_cable" }.freeze

      def initialize(models:)
        @models = models
      end

      def call
        @warnings = []
        # A YAML anchor (`default: &default`, `sqlite3: &sqlite3`) parses as an env; it is not one, and never names a database. Database-less configs are kept only in the standard envs (a real one may leave database unset, e.g. Solid defaults).
        known_envs = %w[development test production] << Rails.env.to_s
        configs = ActiveRecord::Base.configurations.configs_for(include_hidden: true).reject { |c| c.env_name == "default" || (c.database.to_s.empty? && !known_envs.include?(c.env_name)) }
        databases = configs.filter_map do |config|
          entry(config)
        rescue StandardError => e
          @warnings << Collectors.error("databases", "#{config.env_name}/#{config.name}", e)
          nil
        end
        { "databases" => databases, "warnings" => @warnings }
      end

      private

      def entry(config)
        solid = SOLID[config.name] if Gem.loaded_specs[SOLID[config.name]]
        models = config.env_name == Rails.env ? @models.select { |m| m["database"] == config.name }.map { |m| m["name"] } : []
        {
          "env" => config.env_name,
          "name" => config.name,
          "adapter" => config.adapter,
          "database" => config.database,
          "migrations_paths" => config.migrations_paths,
          "replica" => config.replica? == true,
          "solid_component" => solid,
          "models" => models,
          "doc_url" => DocLinks.multiple_databases,
          "gem_links" => solid && DocLinks.gem(solid).transform_keys(&:to_s)
        }
      end
    end
  end
end
