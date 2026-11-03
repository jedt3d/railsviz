class Patient < ApplicationRecord
  has_many :visits, dependent: :destroy
  validates :name, presence: true
  before_save :normalize_name

  private

  def normalize_name
    self.name = name.strip
  end
end
