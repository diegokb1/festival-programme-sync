require "zlib"

class ProgrammeSyncJob < ApplicationJob
  queue_as :default

  retry_on ProgrammeSync::Error, wait: :polynomially_longer, attempts: 5

  LOCK_KEY = Zlib.crc32("programme_sync")

  def perform(generation: 1)
    with_lock do
      ProgrammeSync.new(generation: generation).call
    end
  end

  private

  def with_lock
    connection = ActiveRecord::Base.connection
    raw_result = connection.select_value("SELECT pg_try_advisory_lock(#{LOCK_KEY})")
    acquired = ActiveModel::Type::Boolean.new.cast(raw_result)

    unless acquired
      Rails.logger.info("[ProgrammeSyncJob] skipped: a sync is already in progress")
      return
    end

    yield
  ensure
    connection.execute("SELECT pg_advisory_unlock(#{LOCK_KEY})") if acquired
  end
end
