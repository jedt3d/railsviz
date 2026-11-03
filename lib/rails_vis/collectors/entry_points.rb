# frozen_string_literal: true

require "erb"
require "yaml"

module RailsVis
  module Collectors
    # Lists the ways work enters the app besides HTTP: jobs, recurring tasks, mailers, channels and rake tasks.
    class EntryPoints
      def initialize(repo:)
        @repo = repo
        @warnings = []
      end

      def call
        @warnings = []
        entry_points = {
          "queue_adapter" => part("queue_adapter", nil) { ActiveJob::Base.queue_adapter_name.to_s },
          "jobs" => part("jobs", []) { jobs },
          "recurring" => part("recurring", []) { recurring },
          "mailers" => part("mailers", []) { mailers },
          "channels" => part("channels", []) { channels },
          "rake_tasks" => part("rake_tasks", []) { rake_tasks }
        }
        { "entry_points" => entry_points, "warnings" => @warnings }
      end

      private

      def part(name, empty)
        yield
      rescue StandardError => e
        @warnings << Collectors.error("entry_points", name, e)
        empty
      end

      # App-code descendants of base, sorted by name; each row in its own rescue.
      def app_classes(base, where)
        base.descendants.select(&:name).sort_by(&:name).filter_map do |klass|
          source = Source.for_const(klass, repo: @repo)
          next unless source && Source.app_code?(source["path"], repo: @repo)
          yield klass, source
        rescue StandardError => e
          @warnings << Collectors.error("entry_points", "#{where} #{klass.name}", e)
          nil
        end
      end

      def jobs
        Rails.application.eager_load!
        app_classes(ActiveJob::Base, "job") do |klass, source|
          queue = klass.queue_name
          { "name" => klass.name, "queue" => (queue.to_s if queue.is_a?(String) || queue.is_a?(Symbol)),
            "source" => source, "doc_url" => DocLinks.active_job }
        end
      end

      def recurring
        file = Rails.root.join("config/recurring.yml")
        return [] unless file.file?
        text = file.read
        data = YAML.safe_load(ERB.new(text).result, aliases: true)
        data.flat_map do |env, tasks|
          tasks.map do |name, task|
            line = text.lines.index { |l| l.start_with?("  #{name}:") }
            { "env" => env, "name" => name, "class" => task["class"], "command" => task["command"],
              "queue" => task["queue"], "schedule" => task["schedule"],
              "source" => Source.node(name: name, path: file.to_s, line: line && line + 1, repo: @repo) }
          end
        end
      rescue StandardError, SyntaxError => e
        @warnings << Collectors.warning("entry_points", "recurring: config/recurring.yml: #{e.class}")
        []
      end

      def mailers
        Rails.application.eager_load!
        app_classes(ActionMailer::Base, "mailer") do |klass, source|
          actions = klass.action_methods.sort.map do |action|
            templates = Dir.glob(Rails.root.join("app/views", klass.mailer_name, "#{action}.*").to_s).sort
            { "name" => action, "source" => Source.for_method(klass.instance_method(action), repo: @repo),
              "templates" => templates.map { |t| Source.node(name: File.basename(t), path: t, line: 1, repo: @repo) } }
          end
          { "name" => klass.name, "source" => source, "actions" => actions, "doc_url" => DocLinks.action_mailer }
        end
      end

      def channels
        return [] unless defined?(ActionCable::Channel::Base)
        Rails.application.eager_load!
        app_classes(ActionCable::Channel::Base, "channel") do |klass, source|
          { "name" => klass.name, "source" => source, "doc_url" => DocLinks.action_cable }
        end
      end

      def rake_tasks
        require "rake"
        load_tasks if Rake::Task.tasks.empty?
        root = Rails.root.to_s + File::SEPARATOR
        Rake::Task.tasks.sort_by(&:name).filter_map do |task|
          path, line = task.actions.first&.source_location
          next unless path && File.expand_path(path).start_with?(root) && Source.app_code?(path, repo: @repo)
          { "name" => task.name, "comment" => task.comment,
            "source" => Source.node(name: task.name, path: path, line: line, repo: @repo), "doc_url" => DocLinks.rake }
        end
      end

      # Rake drops `desc` text unless metadata recording is on (the rake CLI turns it on; a dump run from code does not).
      def load_tasks
        recording = Rake::TaskManager.record_task_metadata
        Rake::TaskManager.record_task_metadata = true
        Rails.application.load_tasks
      ensure
        Rake::TaskManager.record_task_metadata = recording
      end
    end
  end
end
