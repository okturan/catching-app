require "test_helper"
require Rails.root.join("db/migrate/20260906000002_revamp_activities_into_plan")

# The truncating round-trip test never sees a row. This one rolls the plan
# migration back over an item with no duration and no description, checks the
# backfill that lets NOT NULL return, then re-applies it and checks that
# positions come back dense in id order.
class RevampActivitiesIntoPlanTest < ActiveSupport::TestCase
  test "down backfills open items before restoring NOT NULL and up renumbers positions densely" do
    event = events(:planning)
    connection.execute(<<~SQL.squish)
      INSERT INTO activities (event_id, name, duration, description, position, created_at, updated_at)
      VALUES (#{event.id}, 'Open ended', NULL, NULL, 7, NOW(), NOW())
    SQL

    ActiveRecord::Migration.suppress_messages { RevampActivitiesIntoPlan.new.migrate(:down) }

    row = connection.select_one("SELECT duration, description FROM activities WHERE name = 'Open ended'")
    assert_equal({ "duration" => 1, "description" => "No description provided" }, row)
    assert_not connection.column_exists?(:activities, :position)
    columns = connection.columns(:activities).index_by(&:name)
    assert_not columns.fetch("duration").null
    assert_not columns.fetch("description").null
    assert connection.check_constraints(:activities).any? { |check| check.name == "activities_duration_positive" }
    assert connection.indexes(:activities).any? { |index| index.name == "index_activities_on_event_id" }
    assert_nil connection.foreign_keys(:activities).find { |key| key.to_table == "events" }.on_delete

    ActiveRecord::Migration.suppress_messages { RevampActivitiesIntoPlan.new.migrate(:up) }

    positions = connection.select_values("SELECT position FROM activities WHERE event_id = #{event.id} ORDER BY id")
    assert_equal [ 0, 1 ], positions, "the fixture item and the inserted one are numbered from zero in id order"
  ensure
    Activity.reset_column_information
  end

  private

  def connection
    ActiveRecord::Base.connection
  end
end
