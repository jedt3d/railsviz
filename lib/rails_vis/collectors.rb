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
      quiet = QUIET_ERRORS.any? { |name| (klass = name.safe_constantize) && exception.is_a?(klass) }
      detail = quiet ? "" : ": #{exception.message.lines.first.to_s.strip}"
      warning(where, "#{prefix}: #{exception.class}#{detail}")
    end
  end
end
