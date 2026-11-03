# frozen_string_literal: true

module RailsVis
  module Collectors
    # Lists app models with their associations, validations, callbacks, columns and indexes.
    class Models
      def initialize(repo:)
        @repo = repo
      end

      def call
        @warnings = []
        Rails.application.eager_load!
        models = ActiveRecord::Base.descendants.reject(&:abstract_class?).sort_by { |k| k.name.to_s }.filter_map do |klass|
          next if klass.name.nil?
          source = Source.for_const(klass, repo: @repo)
          next unless source && Source.app_code?(source["path"], repo: @repo)
          unless klass.table_exists?
            add_warning("#{klass.name}: table #{klass.table_name.inspect} does not exist; model skipped")
            next
          end
          model(klass, source)
        rescue StandardError => e
          add_warning("#{klass.name}: #{e.class}: #{e.message}")
          nil
        end
        { "models" => models, "warnings" => @warnings, "model_names" => models.map { |m| m["name"] } }
      end

      private

      def model(klass, source)
        {
          "name" => klass.name,
          "table" => klass.table_name,
          "database" => klass.connection_db_config.name,
          "source" => source,
          "associations" => klass.reflect_on_all_associations.map { |r| association(r) },
          "validations" => klass.validators.map { |v| validation(v) },
          "callbacks" => callbacks(klass),
          "columns" => klass.columns.map { |c| column(c) },
          "indexes" => klass.connection.indexes(klass.table_name).map { |i| { "name" => i.name, "columns" => Array(i.columns), "unique" => i.unique } }
        }
      end

      def association(reflection)
        {
          "macro" => reflection.macro.to_s,
          "name" => reflection.name.to_s,
          "class_name" => reflection.class_name,
          "foreign_key" => reflection.foreign_key.to_s,
          "through" => reflection.options[:through]&.to_s,
          "dependent" => reflection.options[:dependent]&.to_s,
          "doc_url" => DocLinks.association(reflection.macro)
        }
      end

      def validation(validator)
        {
          "kind" => validator.kind.to_s,
          "attributes" => validator.attributes.map(&:to_s),
          "options" => validator.options.reject { |_, v| v.is_a?(Proc) }.transform_keys(&:to_s),
          "doc_url" => DocLinks.validation(validator.kind)
        }
      end

      # ActiveRecord::Callbacks::CALLBACKS names events like :before_save; the chain is the part after the kind.
      def callbacks(klass)
        chains = ActiveRecord::Callbacks::CALLBACKS.map { |c| c.to_s.sub(/\A(before|after|around)_/, "") }.uniq
        chains.flat_map do |chain|
          klass.public_send("_#{chain}_callbacks").filter_map do |cb|
            next unless cb.filter.is_a?(Symbol)
            next unless klass.method_defined?(cb.filter, true) || klass.private_method_defined?(cb.filter, true)
            source = Source.for_method(klass.instance_method(cb.filter), repo: @repo)
            next unless source && Source.app_code?(source["path"], repo: @repo)
            { "event" => chain, "kind" => cb.kind.to_s, "name" => cb.filter.to_s, "source" => source, "doc_url" => DocLinks.model_callback }
          end
        end
      end

      def column(column)
        { "name" => column.name, "type" => column.sql_type_metadata.type.to_s, "null" => column.null, "default" => column.default }
      end

      def add_warning(message)
        @warnings << Collectors.warning("models", message)
      end
    end
  end
end
