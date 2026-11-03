# frozen_string_literal: true

module RailsVis
  # Shared shape for every collector's warnings.
  module Collectors
    module_function

    def warning(where, message)
      { "where" => where, "message" => message }
    end
  end
end
