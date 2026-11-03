namespace :rails_vis do
  desc "Write doc/rails_vis/data.json and index.html for this app"
  task dump: :environment do
    Rails.application.eager_load!
    RailsVis::Dump.new(root: Rails.root).call
  end

  desc "Write .github/workflows/rails_vis.yml (GitHub Pages) and link it from README.md; FORCE=1 overwrites"
  task :install do
    repo = RailsVis::Repo.detect(Rails.root, repo_url: RailsVis::Config.load(Rails.root).repo_url)
    RailsVis::Install.new(root: Rails.root, repo: repo, force: ENV["FORCE"] == "1").call
  end
end
