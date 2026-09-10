require "rails_helper"

RSpec.describe ProgrammeSync do
  def build_http(records, fail_on_page: nil)
    per_page = MockApi::Dataset::PER_PAGE
    pages    = records.each_slice(per_page).to_a
    stubs    = Faraday::Adapter::Test::Stubs.new

    stubs.get(%r{/mock_api/screenings}) do |env|
      page = Faraday::Utils.parse_query(env.url.query)["page"].to_i

      if fail_on_page && page >= fail_on_page
        [500, {}, { error: "Upstream festival system unavailable" }.to_json]
      else
        body = {
          page: page,
          per_page: per_page,
          total_pages: pages.size,
          total_count: records.size,
          screenings: pages[page - 1] || []
        }
        [200, { "Content-Type" => "application/json" }, body.to_json]
      end
    end

    Faraday.new { |builder| builder.adapter :test, stubs }
  end

  describe "#call" do
    it "creates films, venues and screenings from the upstream payload" do
      http = build_http(MockApi::Dataset.generation_one)

      expect { ProgrammeSync.new(http: http).call }
        .to change(Screening, :count).by(60)
        .and change(Film, :count).by(12)
        .and change(Venue, :count).by(6)
    end

    it "does not create duplicates when run twice" do
      ProgrammeSync.new(http: build_http(MockApi::Dataset.generation_one)).call

      expect { ProgrammeSync.new(http: build_http(MockApi::Dataset.generation_one)).call }
        .to change(Screening, :count).by(0)
        .and change(Film, :count).by(0)
        .and change(Venue, :count).by(0)
    end

    it "updates existing records when the upstream data changes" do
      ProgrammeSync.new(http: build_http(MockApi::Dataset.generation_one)).call

      ProgrammeSync.new(http: build_http(MockApi::Dataset.generation_two)).call

      expect(Venue.find_by(external_id: "VEN-03").name).to eq("City Gallery Auditorium")
      expect(Film.find_by(external_id: "FILM-005").title).to eq("Autumn in Trieste (Director's Cut)")
      expect(Screening.find_by(external_id: "SCR-0001").venue.external_id).to eq("VEN-06")
      expect(Screening.find_by(external_id: "SCR-0010").status).to eq("cancelled")
      expect(Screening.find_by(external_id: "SCR-0061")).to be_present
    end

    it "keeps already-retrieved pages when a later page fails" do
      http = build_http(MockApi::Dataset.generation_one, fail_on_page: 2)

      expect { ProgrammeSync.new(http: http, retry_wait: 0).call }.to raise_error(ProgrammeSync::Error)

      expect(Screening.count).to eq(MockApi::Dataset::PER_PAGE) # only page 1 made it in

      run = SyncRun.last
      expect(run).to be_failed
      expect(run.error_message).to be_present
      expect(run.stats["pages_fetched"]).to eq(1)
    end

    it "retries a transiently failing page before giving up" do
      attempts = 0
      records  = MockApi::Dataset.generation_one.first(5)
      stubs    = Faraday::Adapter::Test::Stubs.new

      stubs.get(%r{/mock_api/screenings}) do |_env|
        attempts += 1
        if attempts < 2
          [500, {}, { error: "boom" }.to_json]
        else
          body = { page: 1, per_page: 25, total_pages: 1, total_count: records.size, screenings: records }
          [200, {}, body.to_json]
        end
      end
      http = Faraday.new { |builder| builder.adapter :test, stubs }

      run = ProgrammeSync.new(http: http, retry_wait: 0).call

      expect(run).to be_success
      expect(Screening.count).to eq(5)
      expect(attempts).to eq(2)
    end

    it "records a SyncRun describing what a successful run did" do
      http = build_http(MockApi::Dataset.generation_one)

      run = ProgrammeSync.new(http: http).call

      expect(run).to be_success
      expect(run.stats["screenings"]).to eq("created" => 60, "updated" => 0)
      expect(run.stats["films"]).to eq("created" => 12, "updated" => 48)
      expect(run.stats["venues"]).to eq("created" => 6, "updated" => 54)
      expect(run.stats["pages_fetched"]).to eq(3)
    end
  end
end
