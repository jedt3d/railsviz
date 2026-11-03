# frozen_string_literal: true

class RailsVis::Railtie < Rails::Railtie
  initializer "rails_vis.root" do |app|
    RailsVis.root ||= app.root
  end

  rake_tasks { load File.expand_path("../tasks/rails_vis.rake", __dir__) }
end
