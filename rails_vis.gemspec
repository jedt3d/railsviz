# frozen_string_literal: true

require_relative "lib/rails_vis/version"

Gem::Specification.new do |spec|
  spec.name = "rails_vis"
  spec.version = RailsVis::VERSION
  spec.authors = ["Worajedt"]
  spec.summary = "Static onboarding dashboard for Rails 8 apps"
  spec.required_ruby_version = ">= 3.3"
  spec.files = Dir["lib/**/*.{rb,rake}"] + ["viewer/index.html", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 8.0", "< 8.2"
end
