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

    it "updates existing records when the upstream data changes, without duplicating them" do
      ProgrammeSync.new(http: build_http(MockApi::Dataset.generation_one)).call

      expect { ProgrammeSync.new(http: build_http(MockApi::Dataset.generation_two)).call }
        .to change(Film, :count).by(0)
        .and change(Venue, :count).by(0)

      expect(Film.where(external_id: "FILM-005").count).to eq(1)
      expect(Venue.where(external_id: "VEN-03").count).to eq(1)

      expect(Venue.find_by(external_id: "VEN-03").name).to eq("City Gallery Auditorium")
      expect(Film.find_by(external_id: "FILM-005").title).to eq("Autumn in Trieste (Director's Cut)")
      expect(Screening.find_by(external_id: "SCR-0001").venue.external_id).to eq("VEN-06")
      expect(Screening.find_by(external_id: "SCR-0010").status).to eq("cancelled")
      expect(Screening.find_by(external_id: "SCR-0061")).to be_present
    end

    it "keeps already-retrieved pages when a later page fails" do
      http = build_http(MockApi::Dataset.generation_one, fail_on_page: 2)

      expect { ProgrammeSync.new(http: http, retry_wait: 0).call }.to raise_error(ProgrammeSync::Error)

      expect(Screening.count).to eq(MockApi::Dataset::PER_PAGE)

      run = SyncRun.last
      expect(run).to be_failed
      expect(run.error_message).to be_present
      expect(run.stats["pages_fetched"]).to eq(1)
    end

    it "isolates a bad record so it doesn't abort the rest of the batch, and reports it" do
      records = MockApi::Dataset.generation_one.first(5)
      records[2]["film"]["title"] = nil

      http = build_http(records)

      run = ProgrammeSync.new(http: http).call

      expect(run).to be_partial
      expect(Screening.count).to eq(4)
      expect(run.stats["errors"].size).to eq(1)
      expect(run.stats["errors"].first["external_id"]).to eq(records[2]["id"])
      expect(run.stats["errors"].first["message"]).to match(/Title can't be blank/)
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

    it "logs a structured summary of a successful run" do
      http = build_http(MockApi::Dataset.generation_one)

      expect(Rails.logger).to receive(:info) do |message|
        payload = JSON.parse(message)
        expect(payload["event"]).to eq("programme_sync.run")
        expect(payload["status"]).to eq("success")
        expect(payload["stats"]["screenings"]).to eq("created" => 60, "updated" => 0)
        expect(payload["duration_ms"]).to be_a(Integer)
      end

      ProgrammeSync.new(http: http).call
    end

    it "logs a structured summary of a failed run" do
      http = build_http(MockApi::Dataset.generation_one, fail_on_page: 2)

      expect(Rails.logger).to receive(:error) do |message|
        payload = JSON.parse(message)
        expect(payload["event"]).to eq("programme_sync.run")
        expect(payload["status"]).to eq("failed")
        expect(payload["error"]).to be_present
      end

      expect { ProgrammeSync.new(http: http, retry_wait: 0).call }.to raise_error(ProgrammeSync::Error)
    end
  end
end
