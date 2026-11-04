# frozen_string_literal: true

module RailsVis
  module Collectors
    # Lists app controllers with their filters, actions, the models each action names and the view it renders.
    class Controllers
      def initialize(repo:, config:, routes:, model_names:)
        @repo = repo
        @config = config
        @routes = routes
        @model_names = model_names
      end

      def call
        @warnings = []
        Rails.application.eager_load!
        classes = ActionController::Base.descendants + ActionController::API.descendants
        controllers = classes.sort_by { |k| k.name.to_s }.filter_map do |klass|
          next if klass.name.nil?
          source = Source.for_const(klass, repo: @repo)
          next unless source && Source.app_code?(source["path"], repo: @repo)
          controller(klass, source)
        rescue StandardError => e
          @warnings << Collectors.error("controllers", klass.name, e)
          nil
        end
        warn_missing_controllers
        { "controllers" => controllers, "warnings" => @warnings }
      end

      private

      def controller(klass, source)
        {
          "name" => klass.name,
          "parent" => klass.superclass.name,
          "source" => source,
          "filters" => klass._process_action_callbacks.filter_map { |cb| filter(klass, cb) },
          "actions" => klass.action_methods.sort.map { |name| action(klass, name) }
        }
      end

      def filter(klass, callback)
        raw = callback.filter
        name, source =
          case raw
          when Symbol
            [raw.to_s, declaration(klass, callback.kind, raw) ||
              (Source.for_method(klass.instance_method(raw), repo: @repo) if klass.method_defined?(raw, true) || klass.private_method_defined?(raw, true))]
          when Proc
            path, line = raw.source_location
            ["(block)", path && Source.node(name: "(block)", path: path, line: line, repo: @repo)]
          else [raw.class.name, nil]
          end
        # Inherited framework callbacks (CSRF, gem-defined blocks) are noise for onboarding; keep app-defined ones only.
        return unless source && Source.app_code?(source["path"], repo: @repo)
        {
          "kind" => callback.kind.to_s,
          "name" => name,
          "only" => action_names(callback.instance_variable_get(:@if), :only),
          "except" => action_names(callback.instance_variable_get(:@unless), :except),
          "source" => source,
          "doc_url" => DocLinks.controller_filter(callback.kind)
        }
      rescue StandardError => e
        @warnings << Collectors.error("controllers", "#{klass.name} filter #{callback.filter.inspect}", e)
        nil
      end

      # The `before_action :name` call site in the nearest app-code ancestor (class or concern) that declares it.
      # Links the row even when the method lives in a gem (Devise's authenticate_user!).
      def declaration(klass, kind, filter_name)
        klass.ancestors.each do |ancestor|
          next if ancestor.name.nil?
          node = Source.for_const(ancestor, repo: @repo)
          next unless node && Source.app_code?(node["path"], repo: @repo)
          file = Object.const_source_location(ancestor.name)&.first
          next unless file && File.file?(file)
          line = BodyScan.callback_line(file, kind.to_s, filter_name.to_s, cache: (@parsed ||= {}))
          return Source.node(name: "#{ancestor.name} #{kind}_action :#{filter_name}", path: file, line: line, repo: @repo) if line
        end
        nil
      end

      # Rails rewrites only:/except: into an ActionFilter inside the callback's :if/:unless list.
      def action_names(conditions, key)
        found = Array(conditions).find do |c|
          c.is_a?(AbstractController::Callbacks::ActionFilter) && c.instance_variable_get(:@conditional_key) == key
        end
        found&.instance_variable_get(:@actions)&.to_a&.sort
      end

      def action(klass, name)
        row = { "name" => name, "source" => nil, "models" => [], "view" => nil }
        method = klass.instance_method(name)
        path, line = method.source_location
        row["source"] = Source.for_method(method, repo: @repo)
        unless path && File.file?(path)
          add_warning("#{klass.name}##{name}: source file not readable (#{path.inspect}); models and view skipped")
          return row
        end
        scan = BodyScan.new(path, name, line)
        row.merge("models" => scan.constants & @model_names, "view" => view(klass, name, scan.inertia_component))
      rescue StandardError => e
        @warnings << Collectors.error("controllers", "#{klass.name}##{name}", e)
        row
      end

      def view(klass, name, component)
        case component
        when String
          page = %w[.tsx .jsx].map { |ext| RailsVis.root.join(@config.pages_dir, "#{component}#{ext}") }.find(&:file?)
          return view_node("inertia", page) if page
          add_warning("#{klass.name}##{name}: Inertia page #{component.inspect} not found under #{@config.pages_dir}")
          nil
        when :dynamic
          add_warning("#{klass.name}##{name}: Inertia component is computed at runtime; view not resolved")
          nil
        else
          template = Templates.find(klass, name)
          template && view_node("template", template.identifier)
        end
      end

      def view_node(kind, path)
        Source.node(name: File.basename(path), path:, line: 1, repo: @repo).slice("path", "url").merge("kind" => kind)
      end

      def warn_missing_controllers
        @routes.filter_map { |r| [r["controller"], r["action"]] if r["controller"] }.uniq.each do |controller, action|
          next if "#{controller.camelize}Controller".safe_constantize
          add_warning("#{controller}##{action}: route points at #{controller.camelize}Controller, which does not exist")
        end
      end

      def add_warning(message)
        @warnings << Collectors.warning("controllers", message)
      end
    end
  end
end
