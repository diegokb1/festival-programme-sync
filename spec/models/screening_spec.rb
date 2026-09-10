require "rails_helper"

RSpec.describe Screening do
  describe "associations" do
    it "belongs to a film and a venue" do
      screening = create(:screening)

      expect(screening.film).to be_a(Film)
      expect(screening.venue).to be_a(Venue)
    end
  end

  describe "validations" do
    it "is valid with the factory defaults" do
      expect(build(:screening)).to be_valid
    end

    it "requires an external_id" do
      screening = build(:screening, external_id: nil)

      expect(screening).not_to be_valid
      expect(screening.errors[:external_id]).to include("can't be blank")
    end

    it "requires external_id to be unique" do
      create(:screening, external_id: "SCR-0001")
      duplicate = build(:screening, external_id: "SCR-0001")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:external_id]).to include("has already been taken")
    end

    it "requires starts_at" do
      screening = build(:screening, starts_at: nil)

      expect(screening).not_to be_valid
      expect(screening.errors[:starts_at]).to include("can't be blank")
    end
  end

  describe "status" do
    it "defaults to scheduled" do
      expect(Screening.new.status).to eq("scheduled")
    end

    it "allows cancelled" do
      screening = build(:screening, status: "cancelled")

      expect(screening).to be_valid
      expect(screening).to be_cancelled
    end

    it "rejects a status outside scheduled/cancelled" do
      expect { build(:screening, status: "postponed") }.to raise_error(ArgumentError)
    end
  end
end
