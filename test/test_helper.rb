ENV["RAILS_ENV"] = "test"

require "rails_vis"
require_relative "dummy/config/environment"
require "minitest/autorun"

RailsVis.root = Rails.root
