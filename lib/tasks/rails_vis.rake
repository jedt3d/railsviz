namespace :rails_vis do
  desc "Write doc/rails_vis/data.json and index.html for this app"
  task dump: :environment do
    Rails.application.eager_load!
    RailsVis::Dump.new(root: Rails.root).call
  end

  desc "Fetch a sample of the links in doc/rails_vis/data.json and report non-200s (RAILS_VIS_LINK_SAMPLE per kind, default 10)"
  task :check_links do
    path = Rails.root.join("doc/rails_vis/data.json")
    abort "run bin/rails rails_vis:dump first" unless path.file?
    checker = RailsVis::CheckLinks.new(JSON.parse(path.read), sample: Integer(ENV.fetch("RAILS_VIS_LINK_SAMPLE", 10)))
    checker.call
    exit 1 if checker.failures.any?
  end
end
