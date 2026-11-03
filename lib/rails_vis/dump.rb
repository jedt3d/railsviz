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
      RailsVis.root = @root # collectors read the global; keep it equal to the root Config and Repo use
    end

    def call
      data = collect
      out = @root.join("doc/rails_vis")
      FileUtils.mkdir_p(out)
      out.join("data.json").write(JSON.pretty_generate(data))
      embedded = ERB::Util.json_escape(JSON.generate(data))
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
      boot = run("boot", empty: {}) { Collectors::Boot.new(repo: repo).call }
      middleware = run("middleware") { Collectors::Middleware.new(repo: repo).call }
      entry_points = run("entry_points", empty: {}) { Collectors::EntryPoints.new(repo: repo).call }
      gems = run("gems") do
        Collectors::Gems.new(repo: repo, middleware: middleware["middleware"],
                             initializers: boot["boot"]["framework_initializers"] || []).call
      end

      {
        "meta" => meta(repo),
        "documents" => documents["documents"],
        "routes" => routes["routes"],
        "controllers" => controllers["controllers"],
        "models" => models["models"],
        "databases" => databases["databases"],
        "boot" => boot["boot"],
        "middleware" => middleware["middleware"],
        "entry_points" => entry_points["entry_points"],
        "gems" => gems["gems"],
        "warnings" => @warnings
      }
    end

    # A failing collector yields its empty shape (a list, or {} for Hash sections) and a warning instead of aborting the dump.
    def run(name, empty: [])
      result = yield
      @warnings.concat(result["warnings"] || [])
      result
    rescue StandardError => e
      @warnings << Collectors.error(name, "collector failed", e)
      { name => empty }
    end

    def meta(repo)
      {
        "schema_version" => 2,
        "app_name" => Rails.application.class.module_parent_name,
        "rails_version" => Rails.version,
        "ruby_version" => RUBY_VERSION,
        "generated_at" => Time.now.utc.iso8601,
        "repo" => repo.to_h
      }
    end
  end
end
