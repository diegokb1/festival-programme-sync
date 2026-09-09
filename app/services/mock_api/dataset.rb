module MockApi
  # The two fixture datasets that sit behind the mock external API.
  #
  # Generation 1 is the starting state (60 screenings). Generation 2 is the SAME
  # upstream data after a batch of edits, and every mutation is chosen to catch a
  # specific class of sync bug:
  #
  #   * 4 screenings move venue        -> proves the sync UPDATES, not just inserts
  #   * 3 screenings are cancelled      -> proves soft state changes propagate
  #   * 1 film is retitled (same id)    -> catches find_or_create_by(:title)
  #   * 1 venue is renamed (same id)    -> catches find_or_create_by(:name)
  #   * 2 screenings are added          -> proves inserts still work
  #   * 1 screening is removed          -> exposes whether deletions are handled
  #
  # The external identifiers are stable across generations on purpose. If the
  # retitled film changed id, the single best check in the exercise would break.
  class Dataset
    PER_PAGE = 25

    FILMS = {
      "FILM-001" => { title: "The Silent Orchard",          synopsis: "A beekeeper's last summer in the hills.",        runtime: 118, year: 2024 },
      "FILM-002" => { title: "Northern Lights Over Naples",  synopsis: "Two strangers share one impossible night.",      runtime: 102, year: 2023 },
      "FILM-003" => { title: "A Quiet Tide",                 synopsis: "A fishing village faces the sea, and itself.",    runtime: 95,  year: 2024 },
      "FILM-004" => { title: "The Cartographer's Daughter",  synopsis: "Maps of places that no longer exist.",           runtime: 134, year: 2022 },
      "FILM-005" => { title: "Autumn in Trieste",            synopsis: "A translator returns to a city of ghosts.",      runtime: 110, year: 2024 },
      "FILM-006" => { title: "Paper Boats",                  synopsis: "Childhood, remembered in fragments.",            runtime: 88,  year: 2023 },
      "FILM-007" => { title: "The Last Vineyard",            synopsis: "A family, a harvest, and a decision.",           runtime: 126, year: 2024 },
      "FILM-008" => { title: "Midnight at the Station",      synopsis: "Everyone is leaving. No one arrives.",           runtime: 99,  year: 2021 },
      "FILM-009" => { title: "Salt and Stone",               synopsis: "A quarry town at the end of an era.",            runtime: 141, year: 2024 },
      "FILM-010" => { title: "The Weight of Water",          synopsis: "A diver confronts what the flood left behind.",  runtime: 107, year: 2023 },
      "FILM-011" => { title: "Small Hours",                  synopsis: "A night shift, told in real time.",              runtime: 93,  year: 2024 },
      "FILM-012" => { title: "The Glassblower",              synopsis: "Craft, obsession and a single perfect vase.",    runtime: 115, year: 2022 }
    }.freeze

    VENUES = {
      "VEN-01" => { name: "Grand Cinema",                  address: "12 Main Street",   capacity: 320 },
      "VEN-02" => { name: "Riverside Cinema",              address: "4 Quay Road",      capacity: 180 },
      "VEN-03" => { name: "City Gallery Screening Room",   address: "1 Museum Square",  capacity: 90  },
      "VEN-04" => { name: "The Old Playhouse",             address: "9 Theatre Lane",   capacity: 240 },
      "VEN-05" => { name: "Harbour Lights",                address: "22 Dock Street",   capacity: 150 },
      "VEN-06" => { name: "The Roxy",                      address: "7 Bridge Street",  capacity: 200 }
    }.freeze

    # ---- Generation 2 mutations, keyed by the external id they touch --------

    # Same film id, new title. The classic "matched on the wrong column" trap.
    FILM_OVERRIDES_G2  = { "FILM-005" => { title: "Autumn in Trieste (Director's Cut)" } }.freeze
    # Same venue id, new name. The trap the shipped VenueSync actually falls into.
    VENUE_OVERRIDES_G2 = { "VEN-03" => { name: "City Gallery Auditorium" } }.freeze

    # screening id => new venue id
    MOVED_VENUES_G2 = {
      "SCR-0001" => "VEN-06",
      "SCR-0002" => "VEN-05",
      "SCR-0003" => "VEN-06",
      "SCR-0004" => "VEN-05"
    }.freeze

    CANCELLED_G2 = %w[SCR-0010 SCR-0011 SCR-0012].freeze
    REMOVED_G2   = %w[SCR-0060].freeze

    ADDED_G2 = [
      { "id" => "SCR-0061", "film_id" => "FILM-001", "venue_id" => "VEN-02", "starts_at" => "2027-03-20T19:30:00Z", "status" => "scheduled" },
      { "id" => "SCR-0062", "film_id" => "FILM-007", "venue_id" => "VEN-04", "starts_at" => "2027-03-21T18:00:00Z", "status" => "scheduled" }
    ].freeze

    # The flat generation-1 screenings, generated deterministically so counts and
    # ids never drift. 60 screenings across the 12 films and 6 venues.
    BASE_SCREENINGS = (1..60).map do |n|
      film_id  = format("FILM-%03d", ((n - 1) % 12) + 1)
      venue_id = format("VEN-%02d",  ((n - 1) % 6) + 1)
      day      = 5 + (n % 12)                       # spread across ~12 festival days
      hour     = [14, 16, 18, 20][n % 4]
      {
        "id"        => format("SCR-%04d", n),
        "film_id"   => film_id,
        "venue_id"  => venue_id,
        "starts_at" => Time.utc(2027, 3, day, hour, 0, 0).iso8601,
        "status"    => "scheduled"
      }
    end.freeze

    class << self
      # Full, nested records for a generation (no pagination applied).
      def records(generation:)
        generation.to_i == 2 ? generation_two : generation_one
      end

      def generation_one
        BASE_SCREENINGS.map { |s| build_record(s) }
      end

      def generation_two
        flat = BASE_SCREENINGS
          .reject  { |s| REMOVED_G2.include?(s["id"]) }
          .map do |s|
            s = s.dup
            s["venue_id"] = MOVED_VENUES_G2[s["id"]] if MOVED_VENUES_G2.key?(s["id"])
            s["status"]   = "cancelled"              if CANCELLED_G2.include?(s["id"])
            s
          end
        flat += ADDED_G2

        flat.map { |s| build_record(s, film_overrides: FILM_OVERRIDES_G2, venue_overrides: VENUE_OVERRIDES_G2) }
      end

      private

      # Turn a flat screening into the nested shape the API returns.
      def build_record(flat, film_overrides: {}, venue_overrides: {})
        {
          "id"        => flat["id"],
          "starts_at" => flat["starts_at"],
          "status"    => flat["status"],
          "film"      => film_json(flat["film_id"], film_overrides[flat["film_id"]] || {}),
          "venue"     => venue_json(flat["venue_id"], venue_overrides[flat["venue_id"]] || {})
        }
      end

      def film_json(id, overrides)
        base = FILMS.fetch(id)
        {
          "id"       => id,
          "title"    => base[:title],
          "synopsis" => base[:synopsis],
          "runtime"  => base[:runtime],
          "year"     => base[:year]
        }.merge(overrides.transform_keys(&:to_s))
      end

      def venue_json(id, overrides)
        base = VENUES.fetch(id)
        {
          "id"       => id,
          "name"     => base[:name],
          "address"  => base[:address],
          "capacity" => base[:capacity]
        }.merge(overrides.transform_keys(&:to_s))
      end
    end
  end
end
