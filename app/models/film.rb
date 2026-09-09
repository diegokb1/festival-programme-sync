class Film < ApplicationRecord
  has_many :screenings, dependent: :destroy

  validates :external_id, presence: true, uniqueness: true
  validates :title, presence: true
end
