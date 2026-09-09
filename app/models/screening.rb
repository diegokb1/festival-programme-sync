class Screening < ApplicationRecord
  belongs_to :film
  belongs_to :venue

  enum :status, { scheduled: "scheduled", cancelled: "cancelled" }, default: "scheduled"

  validates :external_id, presence: true, uniqueness: true
  validates :starts_at, presence: true
end
