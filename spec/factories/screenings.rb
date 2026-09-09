FactoryBot.define do
  factory :screening do
    sequence(:external_id) { |n| format("SCR-%04d", n) }
    film
    venue
    starts_at { Time.utc(2027, 3, 12, 20, 0, 0) }
    status { "scheduled" }
  end
end
