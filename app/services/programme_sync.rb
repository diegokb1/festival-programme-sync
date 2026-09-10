class ProgrammeSync
  Error = Class.new(StandardError)

  DEFAULT_MAX_ATTEMPTS = 3
  DEFAULT_RETRY_WAIT   = 0.5 # seconds, doubled on each retry

  def initialize(
    generation: 1,
    api_url: ENV.fetch("FESTIVAL_API_URL", "http://localhost:3000"),
    http: nil,
    max_attempts: DEFAULT_MAX_ATTEMPTS,
    retry_wait: DEFAULT_RETRY_WAIT
  )
    @generation   = generation
    @max_attempts = max_attempts
    @retry_wait   = retry_wait
    @http         = http || Faraday.new(url: api_url)
  end

  def call
    @sync_run = SyncRun.create!(started_at: Time.current)

    page         = 1
    total_pages  = 1

    while page <= total_pages
      body        = fetch_page(page)
      total_pages = body.fetch("total_pages")

      body.fetch("screenings").each { |record| upsert_screening(record) }

      @sync_run.stats["pages_fetched"] = page
      @sync_run.save!

      page += 1
    end

    @sync_run.succeed!
    log_run
    @sync_run
  rescue => e
    @sync_run.fail!(e)
    log_run(error: e.message)
    raise
  end

  private

  def log_run(error: nil)
    payload = {
      event:       "programme_sync.run",
      sync_run_id: @sync_run.id,
      status:      @sync_run.status,
      duration_ms: ((@sync_run.finished_at - @sync_run.started_at) * 1000).round,
      stats:       @sync_run.stats
    }
    payload[:error] = error if error

    Rails.logger.public_send(error ? :error : :info, payload.to_json)
  end

  def fetch_page(page)
    attempts = 0

    begin
      attempts += 1
      response = @http.get("/mock_api/screenings", page: page, generation: @generation)
      raise Error, "upstream returned #{response.status}" unless response.success?

      JSON.parse(response.body)
    rescue Faraday::Error, Error, JSON::ParserError => e
      raise Error, "failed to fetch page #{page} after #{attempts} attempts: #{e.message}" if attempts >= @max_attempts

      sleep(@retry_wait * attempts)
      retry
    end
  end

  def upsert_screening(record)
    ActiveRecord::Base.transaction do
      film      = upsert_film(record.fetch("film"))
      venue     = upsert_venue(record.fetch("venue"))
      screening = Screening.find_or_initialize_by(external_id: record.fetch("id"))
      created   = screening.new_record?

      screening.film      = film
      screening.venue     = venue
      screening.starts_at = record.fetch("starts_at")
      screening.status    = record.fetch("status")
      screening.save!

      track(:screenings, created)
    end
  end

  def upsert_film(attrs)
    film    = Film.find_or_initialize_by(external_id: attrs.fetch("id"))
    created = film.new_record?

    film.title    = attrs["title"]
    film.synopsis = attrs["synopsis"]
    film.runtime  = attrs["runtime"]
    film.year     = attrs["year"]
    film.save!

    track(:films, created)
    film
  end

  def upsert_venue(attrs)
    venue   = Venue.find_or_initialize_by(external_id: attrs.fetch("id"))
    created = venue.new_record?

    venue.name     = attrs["name"]
    venue.address  = attrs["address"]
    venue.capacity = attrs["capacity"]
    venue.save!

    track(:venues, created)
    venue
  end

  def track(type, created)
    bucket = (@sync_run.stats[type.to_s] ||= { "created" => 0, "updated" => 0 })
    bucket[created ? "created" : "updated"] += 1
  end
end
