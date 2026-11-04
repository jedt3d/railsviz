# frozen_string_literal: true

require "set"

module RailsVis
  module Collectors
    # Per controller action: its template, the partials and components it renders, the route helpers
    # they call (links) and the helpers its body passes to redirect_to. Layouts are read once each.
    class Pages
      INERTIA_WARNING = "Inertia pages: client-side links (<Link href>) are not collected"

      # candidates: [[engine name or nil, root]]; the longest root containing the file wins.
      def self.engine_of(file, candidates)
        candidates.select { |_, root| file.start_with?("#{root}/") }.max_by { |_, root| root.length }&.first
      end

      def initialize(repo:, routes:, controllers:)
        @repo = repo
        @routes = routes
        @controllers = controllers
      end

      def call
        @warnings = []
        @warned = Set.new
        @scans = {}
        @layouts = {}
        @route_keys = @routes.to_set { |r| [r["engine"], r["name"]] }
        engines = Rails::Engine.descendants.reject { |e| e <= Rails::Application }.filter_map do |e|
          [e, e.root.to_s]
        rescue StandardError
          nil
        end
        @candidates = [[nil, Rails.root.to_s]] + engines.map { |e, root| [e.name, root] }
        @proxies = engines.to_h { |e, _| [e.engine_name, e.name] }
        pages = @controllers.flat_map { |row| controller_pages(row) }
        {
          "pages" => pages.sort_by { |p| [p["controller"], p["action"]] },
          "layouts" => @layouts.values.sort_by { |l| l["name"] }.each { |l| l["controllers"] = l["controllers"].uniq.sort },
          "warnings" => @warnings
        }
      end

      private

      def controller_pages(row)
        klass = row["name"].safe_constantize
        unless klass
          add_warning("#{row["name"]}: controller class not loadable; pages skipped")
          return []
        end
        row["actions"].filter_map do |action|
          where = "#{klass.name}##{action["name"]}"
          Collectors.part("pages", where, nil, @warnings) { page_row(klass, action, where) }
        end
      end

      def page_row(klass, action, where)
        page = { "controller" => klass.name, "action" => action["name"], "template" => nil, "format" => nil, "layout" => nil,
                 "partials" => [], "components" => [], "links" => [], "redirects" => redirects(action, where) }
        view = action["view"]
        if view && view["kind"] == "inertia"
          warn_once(:inertia, INERTIA_WARNING)
          path = File.join(@repo.root.to_s, view["path"])
          page["template"] = Source.node(name: File.basename(path), path: path, line: 1, repo: @repo)
        elsif (template = Templates.find(klass, action["name"]))
          read = read(klass, template, where)
          page.merge!("template" => template_node(template), "format" => template.format&.to_s,
                      "layout" => layout(klass, where), "partials" => read[:partials],
                      "components" => read[:components], "links" => read[:links])
        end
        page if page["template"] || page["links"].any? || page["redirects"].any?
      end

      def redirects(action, where)
        source = action["source"]
        return [] unless source && source["path"] && source["line"]
        file = File.join(@repo.root.to_s, source["path"])
        scan = scan_file(file) { File.read(file, encoding: "UTF-8") }
        return [] unless scan
        scan.helpers.filter_map do |h|
          next unless h["redirect"] && h["def"] == action["name"]
          ref = route_ref(h, file)
          ref&.merge("source" => Source.node(name: where, path: file, line: h["line"], repo: @repo))
        end
      end

      # The layout's name; its row (links included) is built the first time any action resolves to it.
      def layout(klass, where)
        @layout_of ||= {}
        template = @layout_of.fetch(klass) do
          @layout_of[klass] = Collectors.part("pages", "#{klass.name} layout", nil, @warnings) { Templates.layout(klass) }
        end
        return unless template
        name = Templates.layout_name(template)
        row = @layouts[name] ||= { "name" => name, "source" => template_node(template), "controllers" => [],
                                   "links" => read(klass, template, where)[:links] }
        row["controllers"] << klass.name
        name
      end

      # Everything reachable from one template; the visited set (by identifier) stops partial cycles.
      def read(klass, template, where)
        acc = { partials: [], components: [], links: [] }
        visit(klass, template, acc, Set[template.identifier], where)
        acc
      end

      def visit(klass, template, acc, seen, where)
        scan = scan_file(template.identifier) { Templates.compile(template) }
        return unless scan
        acc[:links].concat(links(scan, template.identifier))
        scan.partials.each do |name|
          partial = Templates.partial(klass, name, template.virtual_path)
          next warn_once([:partial, name], "#{where}: partial #{name.inspect} not found") unless partial
          next unless seen.add?(partial.identifier)
          acc[:partials] << template_node(partial)
          visit(klass, partial, acc, seen, where)
        end
        scan.components.each { |const| component(const, acc, seen, where) }
      end

      # The component's sidecar template when it has one, else its class file read as Ruby (a call method).
      def component(const, acc, seen, where)
        klass = const.safe_constantize
        path = klass && Object.const_source_location(klass.name)&.first
        return warn_once([:component, const], "#{where}: component #{const} not found") unless path
        return unless seen.add?(path)
        acc[:components] << Source.for_const(klass, repo: @repo)
        sidecar = Dir.glob(path.sub(/\.rb\z/, ".*")).reject { |f| f.end_with?(".rb") }.min
        scan = if sidecar
                 scan_file(sidecar) { Templates.compile_file(sidecar) }
               else
                 scan_file(path) { File.read(path, encoding: "UTF-8") }
               end
        acc[:links].concat(links(scan, sidecar || path)) if scan
      end

      def links(scan, file)
        scan.helpers.filter_map do |h|
          ref = route_ref(h, file)
          ref&.merge("form" => h["form"], "method" => h["method"],
                     "source" => Source.node(name: h["name"], path: file, line: h["line"], repo: @repo))
        end
      end

      # { "stem", "engine" } when the helper names a route of that engine; nil drops the call.
      def route_ref(helper, file)
        engine =
          case helper["receiver"]
          when nil then self.class.engine_of(file, @candidates)
          when "main_app" then nil
          when String then @proxies.fetch(helper["receiver"]) { return nil }
          else return nil
          end
        { "stem" => helper["stem"], "engine" => engine } if @route_keys.include?([engine, helper["stem"]])
      end

      # One parse per file per dump; a parse error or a failed compile is warned once and the file read as far as it goes.
      def scan_file(path)
        return @scans[path] if @scans.key?(path)
        @scans[path] = begin
          scan = ViewScan.new(yield, path: @repo.relative(path))
          add_warning(scan.error) if scan.error
          scan
        rescue StandardError => e
          @warnings << Collectors.error("pages", @repo.relative(path), e)
          nil
        end
      end

      def template_node(template)
        name = template.virtual_path.sub(%r{[^/]*\z}, File.basename(template.identifier)) # "patients/_row.html.erb"
        Source.node(name: name, path: template.identifier, line: 1, repo: @repo)
      end

      def warn_once(key, message)
        add_warning(message) if @warned.add?(key)
        nil
      end

      def add_warning(message)
        @warnings << Collectors.warning("pages", message)
      end
    end
  end
end
