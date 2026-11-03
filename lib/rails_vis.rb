# frozen_string_literal: true

require "rails"
require "active_support/core_ext/module/attribute_accessors"
require_relative "rails_vis/version"

module RailsVis
  class Error < StandardError; end

  mattr_accessor :root
end

require_relative "rails_vis/railtie"
