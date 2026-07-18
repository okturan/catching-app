require "test_helper"
require Rails.root.join("db/migrate/20260710000000_harden_data_integrity")

class HardenDataIntegrityTest < ActiveSupport::TestCase
  test "normalizes legacy finalized event ranges before constraints are added" do
    connection.create_table(:legacy_events, temporary: true) do |table|
      table.string :label, null: false
      table.boolean :status
      table.datetime :start_time
      table.datetime :end_time
    end
    connection.execute("ALTER TABLE legacy_events RENAME TO events")
    connection.execute <<~SQL.squish
      INSERT INTO events (label, status, start_time, end_time) VALUES
        ('single slot', TRUE, '2030-01-15 10:00:00', '2030-01-15 10:00:00'),
        ('multiple slots', TRUE, '2030-01-15 10:00:00', '2030-01-15 12:00:00'),
        ('missing range', TRUE, '2030-01-15 10:00:00', NULL),
        ('reversed range', TRUE, '2030-01-15 12:00:00', '2030-01-15 10:00:00')
    SQL

    HardenDataIntegrity.new.send(:normalize_finalized_events)

    assert_equal 1, matching_legacy_events("label = 'single slot' AND status = TRUE AND end_time = start_time + INTERVAL '1 hour'")
    assert_equal 1, matching_legacy_events("label = 'multiple slots' AND status = TRUE AND end_time = '2030-01-15 13:00:00'")
    assert_equal 2, matching_legacy_events("status = FALSE AND start_time IS NULL AND end_time IS NULL")
    assert_raises(ActiveRecord::IrreversibleMigration) { HardenDataIntegrity.new.down }
  ensure
    connection.execute("DROP TABLE IF EXISTS pg_temp.events")
  end

  private

  def connection
    ActiveRecord::Base.connection
  end

  def matching_legacy_events(condition)
    connection.select_value("SELECT COUNT(*) FROM events WHERE #{condition}").to_i
  end
end
