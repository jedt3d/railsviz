# frozen_string_literal: true

class RailsVis::Railtie < Rails::Railtie
  rake_tasks { load File.expand_path("../tasks/rails_vis.rake", __dir__) }
end
