namespace :dummy do
  desc "Prints a report"
  task report: :environment do
    puts "report"
  end
end
