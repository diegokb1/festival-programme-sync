class SyncRun < ApplicationRecord
  enum :status, { running: "running", success: "success", partial: "partial", failed: "failed" }, default: "running"

  validates :started_at, presence: true

  def succeed!
    update!(status: :success, finished_at: Time.current)
  end

  def partial!
    update!(status: :partial, finished_at: Time.current)
  end

  def fail!(error)
    update!(status: :failed, finished_at: Time.current, error_message: error.message)
  end
end
