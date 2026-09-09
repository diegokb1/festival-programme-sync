class CreateSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_runs do |t|
      t.string :status, null: false, default: "running"
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.text :error_message
      t.jsonb :stats, null: false, default: {}

      t.timestamps
    end

    add_index :sync_runs, :status
    add_index :sync_runs, :started_at
  end
end
