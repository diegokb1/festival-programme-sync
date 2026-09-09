class Venue < ApplicationRecord
  has_many :screenings, dependent: :destroy

  validates :external_id, presence: true, uniqueness: true
  validates :name, presence: true
end
