# frozen_string_literal: true

require "rails"
require "active_support/core_ext/module/attribute_accessors"
require_relative "rails_vis/version"
require_relative "rails_vis/config"
require_relative "rails_vis/repo"
require_relative "rails_vis/source"
require_relative "rails_vis/templates"
require_relative "rails_vis/body_scan"
require_relative "rails_vis/doc_links"
require_relative "rails_vis/collectors"
require_relative "rails_vis/collectors/routes"
require_relative "rails_vis/collectors/controllers"
require_relative "rails_vis/collectors/models"
require_relative "rails_vis/collectors/databases"
require_relative "rails_vis/collectors/documents"
require_relative "rails_vis/collectors/boot"
require_relative "rails_vis/collectors/middleware"
require_relative "rails_vis/collectors/gems"
require_relative "rails_vis/collectors/entry_points"
require_relative "rails_vis/dump"
require_relative "rails_vis/check_links"
require_relative "rails_vis/install"

module RailsVis
  class Error < StandardError; end

  mattr_accessor :root
end

require_relative "rails_vis/railtie"
