ENV["RAILS_ENV"] = "test"

require "rails_vis"
require_relative "dummy/config/environment"
ActiveRecord::Migration.maintain_test_schema!
require "minitest/autorun"

