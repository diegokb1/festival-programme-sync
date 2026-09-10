require "rails_helper"

RSpec.describe ProgrammeSyncJob do
  def with_other_session
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    raw = PG.connect(
      host: config[:host],
      port: config[:port],
      dbname: config[:database],
      user: config[:username],
      password: config[:password]
    )
    yield raw
  ensure
    raw&.close
  end

  def other_session_acquired_lock?(raw)
    ActiveModel::Type::Boolean.new.cast(raw.exec("SELECT pg_try_advisory_lock(#{described_class::LOCK_KEY})").getvalue(0, 0))
  end

  describe "#perform" do
    it "delegates to ProgrammeSync for the given generation" do
      sync = instance_double(ProgrammeSync, call: true)
      allow(ProgrammeSync).to receive(:new).with(generation: 2).and_return(sync)

      described_class.new.perform(generation: 2)

      expect(sync).to have_received(:call)
    end

    it "defaults to generation 1" do
      sync = instance_double(ProgrammeSync, call: true)
      allow(ProgrammeSync).to receive(:new).with(generation: 1).and_return(sync)

      described_class.new.perform

      expect(sync).to have_received(:call)
    end

    it "skips the run when another session already holds the advisory lock" do
      with_other_session do |raw|
        raw.exec("SELECT pg_advisory_lock(#{described_class::LOCK_KEY})")

        expect(ProgrammeSync).not_to receive(:new)

        described_class.new.perform
      ensure
        raw.exec("SELECT pg_advisory_unlock(#{described_class::LOCK_KEY})")
      end
    end

    it "releases the lock after a run so a different session can acquire it" do
      sync = instance_double(ProgrammeSync, call: true)
      allow(ProgrammeSync).to receive(:new).and_return(sync)

      described_class.new.perform

      with_other_session do |raw|
        acquired = other_session_acquired_lock?(raw)
        raw.exec("SELECT pg_advisory_unlock(#{described_class::LOCK_KEY})") if acquired

        expect(acquired).to be(true)
      end
    end

    it "releases the lock even when ProgrammeSync raises" do
      allow(ProgrammeSync).to receive(:new).and_raise(ProgrammeSync::Error, "boom")

      expect { described_class.new.perform }.to raise_error(ProgrammeSync::Error)

      with_other_session do |raw|
        acquired = other_session_acquired_lock?(raw)
        raw.exec("SELECT pg_advisory_unlock(#{described_class::LOCK_KEY})") if acquired

        expect(acquired).to be(true)
      end
    end
  end

  it "retries on ProgrammeSync::Error" do
    handled_classes = described_class.rescue_handlers.map(&:first)
    expect(handled_classes).to include("ProgrammeSync::Error")
  end
end
