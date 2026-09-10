require "rails_helper"

RSpec.describe VenueSync do
  describe "#call" do
    it "creates a venue that doesn't exist yet" do
      payload = [
        { "id" => "VEN-01", "name" => "Grand Cinema", "address" => "12 Main Street", "capacity" => 320 }
      ]

      expect { VenueSync.new(payload).call }.to change(Venue, :count).by(1)

      venue = Venue.find_by(external_id: "VEN-01")
      expect(venue).to have_attributes(
        name: "Grand Cinema",
        address: "12 Main Street",
        capacity: 320
      )
    end

    it "updates the existing venue when it is renamed upstream, instead of creating a duplicate" do
      VenueSync.new([
        { "id" => "VEN-03", "name" => "City Gallery Screening Room", "address" => "1 Museum Square", "capacity" => 90 }
      ]).call

      expect {
        VenueSync.new([
          { "id" => "VEN-03", "name" => "City Gallery Auditorium", "address" => "1 Museum Square", "capacity" => 90 }
        ]).call
      }.to change(Venue, :count).by(0)

      venue = Venue.find_by(external_id: "VEN-03")
      expect(venue.name).to eq("City Gallery Auditorium")
    end

    it "skips a bad record but still processes the rest of the batch" do
      payload = [
        { "name" => "Missing an id" },
        { "id" => "VEN-02", "name" => "Riverside Cinema", "address" => "4 Quay Road", "capacity" => 180 }
      ]

      expect { VenueSync.new(payload).call }.to change(Venue, :count).by(1)

      expect(Venue.find_by(external_id: "VEN-02")).to be_present
    end
  end
end
