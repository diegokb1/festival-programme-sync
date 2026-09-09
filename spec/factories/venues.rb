FactoryBot.define do
  factory :venue do
    sequence(:external_id) { |n| format("VEN-%02d", n) }
    sequence(:name) { |n| "Venue #{n}" }
    address { "1 Example Street" }
    capacity { 200 }
  end
end
