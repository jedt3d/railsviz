# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module RailsVis
  # Runs every collector and writes doc/rails_vis/data.json plus the viewer with that JSON embedded.
  # data.json holds only collector output and the fields below, never config or ENV values.
  class Dump
    VIEWER = File.expand_path("../../viewer/index.html", __dir__)
    TOKEN = "<!--RAILS_VIS_DATA-->"

    def initialize(root:)
      @root = Pathname.new(root.to_s)
    end

    def call
      data = collect
      out = @root.join("doc/rails_vis")
      FileUtils.mkdir_p(out)
      out.join("data.json").write(JSON.pretty_generate(data))
      embedded = JSON.generate(data).gsub("</", "<\\/")
      script = %(<script id="rails-vis-data" type="application/json">#{embedded}</script>)
      out.join("index.html").write(File.read(VIEWER).sub(TOKEN) { script })
      out
    end

    private

    def collect
      config = Config.load(@root)
      repo = Repo.detect(@root, repo_url: config.repo_url)
      @warnings = repo.warnings.map { |message| Collectors.warning("repo", message) }

      models = run("models") { Collectors::Models.new(repo: repo).call }
      routes = run("routes") { Collectors::Routes.new(repo: repo).call }
      controllers = run("controllers") do
        Collectors::Controllers.new(repo: repo, config: config, routes: routes["routes"], model_names: models["model_names"] || []).call
      end
      databases = run("databases") { Collectors::Databases.new(models: models["models"]).call }
      documents = run("documents") { Collectors::Documents.new(config: config, repo: repo).call }

      {
        "meta" => meta(repo),
        "documents" => documents["documents"],
        "routes" => routes["routes"],
        "controllers" => controllers["controllers"],
        "models" => models["models"],
        "databases" => databases["databases"],
        "warnings" => @warnings
      }
    end

    # A failing collector yields an empty list and a warning instead of aborting the dump.
    def run(name)
      result = yield
      @warnings.concat(result["warnings"] || [])
      result
    rescue StandardError => e
      @warnings << Collectors.warning(name, "#{e.class}: #{e.message}")
      { name => [] }
    end

    def meta(repo)
      {
        "schema_version" => 1,
        "app_name" => Rails.application.class.module_parent_name,
        "rails_version" => Rails.version,
        "ruby_version" => RUBY_VERSION,
        "generated_at" => Time.now.utc.iso8601,
        "repo" => repo.to_h
      }
    end
  end
end
