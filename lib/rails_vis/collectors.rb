# frozen_string_literal: true

module RailsVis
  # Shared shape for every collector's warnings.
  module Collectors
    # Their messages can carry a database host or username, so only the class name is reported.
    QUIET_ERRORS = %w[ActiveRecord::ActiveRecordError PG::Error SQLite3::Exception SystemCallError].freeze

    module_function

    def warning(where, message)
      { "where" => where, "message" => message }
    end

    def error(where, prefix, exception)
      # By name only: resolving "SQLite3::Exception" would load the sqlite3 gem, and a LoadError aborts the dump.
      names = exception.class.ancestors.filter_map(&:name)
      detail = names.intersect?(QUIET_ERRORS) ? "" : ": #{exception.message.lines.first.to_s.strip}"
      warning(where, "#{prefix}: #{exception.class.name || exception.class}#{detail}")
    end
  end
end
