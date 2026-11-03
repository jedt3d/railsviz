# frozen_string_literal: true

require "yaml"

module RailsVis
  class Config
    DEFAULTS = {
      "docs" => ["docs/**/*.md"],
      "exclude" => ["docs/superpowers/**"],
      "start_here" => [],
      "pages_dir" => "app/frontend/pages",
      "repo_url" => nil
    }.freeze

    attr_reader(*DEFAULTS.keys)

    def self.load(root)
      file = File.join(root.to_s, "config", "rails_vis.yml")
      data = File.exist?(file) ? (YAML.safe_load_file(file) || {}) : {}
      new(DEFAULTS.merge(data.slice(*DEFAULTS.keys)))
    end

    def initialize(values)
      values.each { |key, value| instance_variable_set("@#{key}", value) }
    end
  end
end
