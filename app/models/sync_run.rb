class SyncRun < ApplicationRecord
  enum :status, { running: "running", success: "success", failed: "failed" }, default: "running"

  validates :started_at, presence: true

  def record!(type)
    stats[type.to_s] ||= { "created" => 0, "updated" => 0 }
    yield(stats[type.to_s]) if block_given?
  end

  def succeed!
    update!(status: :success, finished_at: Time.current)
  end

  def fail!(error)
    update!(status: :failed, finished_at: Time.current, error_message: error.message)
  end
end
