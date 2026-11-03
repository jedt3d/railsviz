class PatientMailer < ApplicationMailer
  def welcome = mail(to: "patient@example.com", subject: "Welcome")

  def reminder = mail(to: "patient@example.com", subject: "Reminder")
end
