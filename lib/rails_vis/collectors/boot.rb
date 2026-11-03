# frozen_string_literal: true

module RailsVis
  module Collectors
    # Lists what runs at boot: application and environment files, initializers in load order,
    # the ENV keys config reads and the credential key names. Values are never read or kept.
    class Boot
      ENV_REFERENCE = /ENV(?:\.fetch\(|\[)\s*["']([A-Z][A-Z0-9_]*)["']/

      def initialize(repo:)
        @repo = repo
      end

      def call
        @warnings = []
        initializers = part("initializers", { "app_initializers" => [], "framework_initializers" => [] }) { initializer_groups }
        boot = {
          "application" => part("application", nil) { Source.for_const(Rails.application.class, repo: @repo) },
          "environments" => part("environments", []) { file_nodes(Rails.root.glob("config/environments/*.rb").sort) },
          "initializer_files" => part("initializer_files", []) { file_nodes(initializer_paths) },
          **initializers,
          "env_keys" => part("env_keys", []) { env_keys },
          "credentials_keys" => part("credentials", nil) { credentials_keys },
          "doc_url" => DocLinks.configuring
        }
        { "boot" => boot, "warnings" => @warnings }
      end

      private

      def part(name, empty)
        yield
      rescue StandardError => e
        @warnings << Collectors.error("boot", name, e)
        empty
      end

      def file_nodes(files)
        files.map do |file|
          Source.node(name: File.basename(file.to_s, ".rb"), path: file.to_s, line: 1, repo: @repo)
        end
      end

      # Rails' own list: each existent directory in turn, files sorted by name within it.
      def initializer_paths
        Rails.application.paths["config/initializers"].existent
      end

      def initializer_groups
        app = []
        groups = {}
        Rails.application.initializers.tsort_each do |init|
          path, line = init.block&.source_location
          railtie = init.context_class.name
          # Under Rails.root too: a gem checked out inside the repo (rails_vis in its own dummy) is not the app's initializer.
          if path && Source.app_code?(path, repo: @repo) && File.expand_path(path).start_with?(Rails.root.to_s + File::SEPARATOR)
            app << { "name" => init.name.to_s, "railtie" => railtie,
                     "source" => Source.node(name: init.name.to_s, path: path, line: line, repo: @repo) }
          else
            group = (groups[railtie] ||= { "railtie" => railtie, "count" => 0, "url" => nil })
            group["count"] += 1
            group["url"] ||= (Source.gem_url(path, repo: @repo) if path)
          end
        end
        { "app_initializers" => app, "framework_initializers" => groups.values }
      end

      def env_keys
        found = Hash.new { |h, k| h[k] = [] }
        Rails.root.glob("config/**/*.{rb,yml,yaml,erb}").sort_by(&:to_s).each do |file|
          next unless Source.app_code?(file.to_s, repo: @repo)
          file.each_line.with_index(1) do |text, line|
            text.scan(ENV_REFERENCE) do |(key)|
              found[key] << Source.node(name: key, path: file.to_s, line: line, repo: @repo)
            end
          end
        rescue StandardError => e
          @warnings << Collectors.error("boot", "env_keys #{@repo.relative(file.to_s)}", e)
        end
        found.sort.map { |key, refs| { "key" => key, "references" => refs } }
      end

      def credentials_keys
        credentials = Rails.application.credentials
        keys = (credentials.config.keys.map(&:to_s).sort if credentials.key.present?)
        return keys if keys
        @warnings << Collectors.warning("boot", "credentials: no master key available; credential keys omitted (values are never collected)")
        nil
      rescue StandardError
        @warnings << Collectors.warning("boot", "credentials: no master key available; credential keys omitted (values are never collected)")
        nil
      end
    end
  end
end
