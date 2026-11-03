# Fixture for rails_vis: authenticate_user! is defined by a gem in real apps (Devise); here it is absent,
# so only the declaration line is app code. set_locale is app code and shares the declaration.
class AdminController < ApplicationController
  include Audited
  before_action :authenticate_user!, :set_locale
  def index = head(:ok)
  private
  def set_locale = nil
end
