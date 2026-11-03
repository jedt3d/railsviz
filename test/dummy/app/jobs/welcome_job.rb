class WelcomeJob < ApplicationJob
  queue_as :mailers

  def perform(patient_id) = nil
end
