# Keeps our local venue records in step with the upstream festival system.
#
# Inherited from the previous programming integration. Given an array of venue
# hashes from the API, it upserts each one into our venues table.
#
#   VenueSync.new(venues_payload).call
#
# where each entry looks like:
#   { "id" => "VEN-01", "name" => "Grand Cinema", "address" => "...", "capacity" => 320 }
class VenueSync
  def initialize(venues)
    @venues = venues
  end

  def call
    @venues.each do |attrs|
      venue = Venue.find_or_initialize_by(name: attrs["name"])
      venue.external_id = attrs.fetch("id")
      venue.address     = attrs["address"]
      venue.capacity    = attrs["capacity"]
      venue.save!
    end
  end
end
