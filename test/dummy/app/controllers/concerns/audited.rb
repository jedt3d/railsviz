# Fixture for rails_vis: a filter declared inside a concern (issue 23).
module Audited
  extend ActiveSupport::Concern
  included do
    after_action :audit
  end
  private
  def audit = nil
end
