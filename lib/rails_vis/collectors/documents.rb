# frozen_string_literal: true

require "yaml"

module RailsVis
  module Collectors
    # Reads the project's Markdown documents, their optional YAML front matter, and resolves `related` to code nodes.
    class Documents
      # Tolerates CRLF and front matter that ends at EOF; a BOM is stripped when the file is read.
      FRONT_MATTER = /\A---\r?\n(.*?)\r?\n---(?:\r?\n|\z)/m
      FOLDER_KINDS = { "decisions" => "decision", "research" => "reference" }.freeze
      DIAGRAM_FOLDERS = %w[workflows sequences ui domain security].freeze
      # File.fnmatch? with FNM_PATHNAME treats a trailing "**" as one segment; "**/*" matches any depth.
      FNM = File::FNM_PATHNAME | File::FNM_EXTGLOB

      def initialize(config:, repo:)
        @config = config
        @repo = repo
      end

      def call
        @warnings = []
        documents = files.filter_map do |rel, base|
          document(rel, base)
        rescue StandardError => e
          add_warning("#{rel}: #{e.class}: #{e.message}")
          nil
        end
        { "documents" => documents, "warnings" => @warnings }
      end

      private

      def root = RailsVis.root

      # [Rails-root-relative path, static folder of the glob that matched it], minus excluded paths.
      def files
        found = @config.docs.flat_map do |pattern|
          base = File.dirname("#{pattern.split(/[*?\[{]/, 2).first}_")
          Dir.glob(pattern, base: root.to_s).map { |rel| [rel, base] }
        end
        found.uniq(&:first).reject { |rel, _| excluded?(rel) }.sort
      end

      def excluded?(rel)
        @config.exclude.any? do |pattern|
          pattern = "#{pattern}/*" if pattern.end_with?("/**")
          File.fnmatch?(pattern, rel, FNM)
        end
      end

      def document(rel, base)
        text = File.read(root.join(rel), mode: "r:bom|utf-8")
        meta, body = front_matter(rel, text)
        start = @config.start_here.index(rel)
        {
          "path" => @repo.relative(root.join(rel)),
          "title" => meta["title"] || body[/^# (.+)$/, 1]&.strip || File.basename(rel, ".*"),
          "kind" => meta["kind"] || kind(rel, base, body),
          "audience" => meta["audience"] || "all",
          "order" => start ? start + 1 : meta["order"],
          "related" => Array(meta["related"]).filter_map { |entry| related(rel, entry.to_s) },
          "body" => body,
          "has_mermaid" => mermaid?(body)
        }
      end

      def front_matter(rel, text)
        match = FRONT_MATTER.match(text)
        return [{}, text] unless match
        data = YAML.safe_load(match[1], permitted_classes: [Date, Time])
        [data.is_a?(Hash) ? data : {}, match.post_match]
      rescue Psych::Exception => e
        add_warning("#{rel}: front matter could not be loaded (#{e.message}); treated as absent")
        [{}, text]
      end

      def kind(rel, base, body)
        # Kind follows the first folder below the docs root, so docs/domain/sub/x.md is a domain/ document.
        segments = Pathname.new(rel).relative_path_from(base).each_filename.to_a
        return "overview" if segments.size == 1
        folder = segments.first
        return mermaid?(body) ? "diagram" : "reference" if DIAGRAM_FOLDERS.include?(folder)
        FOLDER_KINDS.fetch(folder, "reference")
      end

      def mermaid?(body) = body.match?(/^```mermaid\b/)

      def related(rel, entry)
        path = root.join(entry)
        node =
          if !entry.empty? && path.exist?
            Source.node(name: entry, path: path.to_s, line: 1, repo: @repo)
          elsif (m = entry.match(/\A([A-Z][\w:]*)#(\w+[?!=]?)\z/))
            Source.for_method(Object.const_get(m[1]).instance_method(m[2]), repo: @repo)
          elsif entry.match?(/\A[A-Z][\w:]*\z/)
            Source.for_const(Object.const_get(entry), repo: @repo)
          end
        node || unresolved(rel, entry)
      rescue NameError
        unresolved(rel, entry)
      end

      def unresolved(rel, entry)
        add_warning("#{rel}: related entry #{entry.inspect} does not resolve to a file, class or method; dropped")
        nil
      end

      def add_warning(message)
        @warnings << Collectors.warning("documents", message)
      end
    end
  end
end
