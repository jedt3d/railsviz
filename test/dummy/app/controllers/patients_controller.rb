class PatientsController < ApplicationController
  before_action :load_patient, only: %i[show]
  def index  = render(:index, locals: { patients: Patient.all })
  def show   = render(inertia: "Patients/Show", props: { patient: @patient })
  def export = render(inertia: component_name)
  private
  def load_patient = @patient = Patient.find(params[:id])
  def component_name = "Patients/Export"
end
