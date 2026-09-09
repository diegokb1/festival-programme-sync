FactoryBot.define do
  factory :film do
    sequence(:external_id) { |n| format("FILM-%03d", n) }
    sequence(:title) { |n| "Film #{n}" }
    synopsis { "A synopsis." }
    runtime { 100 }
    year { 2024 }
  end
end
