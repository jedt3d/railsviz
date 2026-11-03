namespace :rails_vis do
  desc "Write doc/rails_vis/data.json and index.html for this app"
  task dump: :environment do
    RailsVis.root = Rails.root
    Rails.application.eager_load!
    RailsVis::Dump.new(root: Rails.root).call
  end
end
