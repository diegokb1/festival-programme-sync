require "rails_helper"

RSpec.describe Venue do
  describe "associations" do
    it "destroys its screenings when destroyed" do
      venue     = create(:venue)
      screening = create(:screening, venue: venue)

      expect { venue.destroy }.to change(Screening, :count).by(-1)
      expect { screening.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "validations" do
    it "is valid with the factory defaults" do
      expect(build(:venue)).to be_valid
    end

    it "requires an external_id" do
      venue = build(:venue, external_id: nil)

      expect(venue).not_to be_valid
      expect(venue.errors[:external_id]).to include("can't be blank")
    end

    it "requires external_id to be unique" do
      create(:venue, external_id: "VEN-01")
      duplicate = build(:venue, external_id: "VEN-01")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:external_id]).to include("has already been taken")
    end

    it "requires a name" do
      venue = build(:venue, name: nil)

      expect(venue).not_to be_valid
      expect(venue.errors[:name]).to include("can't be blank")
    end
  end
end
