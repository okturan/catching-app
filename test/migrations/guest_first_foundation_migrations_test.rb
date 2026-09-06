require "test_helper"
%w[
  20260902000001_create_participants
  20260902000002_add_scheduling_grid_to_events
  20260902000003_reparent_time_slots_to_participants
  20260902000004_drop_user_ownership
  20260905000001_drop_dead_user_columns
  20260906000001_add_planning_state_to_events_and_participants
  20260906000002_revamp_activities_into_plan
  20260906000003_extend_mail_delivery_kinds
].each { |file| require Rails.root.join("db/migrate/#{file}") }

# Runs the foundation and planning migrations down and up inside the test
# transaction on an emptied database and checks the result against the
# committed schema. Between down and up only connection introspection is used:
# no model may be queried while the tables have their legacy shape.
class GuestFirstFoundationMigrationsTest < ActiveSupport::TestCase
  MIGRATIONS = [
    CreateParticipants, AddSchedulingGridToEvents, ReparentTimeSlotsToParticipants, DropUserOwnership, DropDeadUserColumns,
    AddPlanningStateToEventsAndParticipants, RevampActivitiesIntoPlan, ExtendMailDeliveryKinds
  ].freeze
  MODELS = [ Participant, MailDelivery, TimeSlot, Event, User, Activity ].freeze

  test "the migrations round-trip and reproduce db/schema.rb" do
    connection.execute("TRUNCATE TABLE mail_deliveries, time_slots, participants, activities, events, users RESTART IDENTITY CASCADE")

    ActiveRecord::Migration.suppress_messages do
      MIGRATIONS.reverse_each { |migration| migration.new.migrate(:down) }

      assert connection.table_exists?(:user_events)
      assert connection.column_exists?(:events, :user_id)
      assert connection.column_exists?(:events, :meeting_medium)
      assert connection.column_exists?(:time_slots, :user_id)
      assert connection.column_exists?(:time_slots, :end_time)
      assert_not connection.table_exists?(:participants)
      assert_not connection.table_exists?(:mail_deliveries)
      assert_not connection.column_exists?(:events, :slot_minutes)
      assert connection.column_exists?(:users, :phone_number)
      assert_not connection.column_exists?(:events, :revision)
      assert_not connection.column_exists?(:activities, :position)
      assert connection.check_constraints(:activities).any? { |check| check.name == "activities_duration_positive" }

      MIGRATIONS.each { |migration| migration.new.migrate(:up) }
    end

    composite = connection.foreign_keys(:time_slots).find { |key| key.name == "fk_time_slots_participant_in_event" }
    assert_equal %w[participant_id event_id], Array(composite.column)
    assert connection.indexes(:participants).any? { |index| index.name == "index_participants_one_organizer_per_event" && index.where.present? }
    assert connection.check_constraints(:time_slots).any? { |check| check.name == "time_slots_start_time_quarter_hour" }
    assert_not connection.column_exists?(:users, :phone_number)
    assert connection.check_constraints(:events).any? { |check| check.name == "events_offer_revision_counts" }
    assert connection.check_constraints(:participants).any? { |check| check.name == "participants_voided_is_open_reply" }
    assert connection.check_constraints(:activities).any? { |check| check.name == "activities_duration_bounded" }
    assert_equal :cascade, connection.foreign_keys(:activities).find { |key| key.to_table == "events" }.on_delete

    dump = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, dump)
    assert_equal File.read(Rails.root.join("db/schema.rb")).strip, dump.string.strip,
      "db/schema.rb differs from the migrations; regenerate it with bin/rails db:migrate"
  ensure
    MODELS.each(&:reset_column_information)
  end

  test "the backfill maps organizers, invitees and orphans" do
    connection.execute("TRUNCATE TABLE mail_deliveries, time_slots, participants, activities, events, users RESTART IDENTITY CASCADE")

    ActiveRecord::Migration.suppress_messages do
      MIGRATIONS.reverse_each { |migration| migration.new.migrate(:down) }

      connection.execute(<<~SQL.squish)
        INSERT INTO users (id, email, encrypted_password, first_name, last_name, created_at, updated_at) VALUES
          (1, 'Org@Example.com', 'x', 'Olivia', 'Owner', NOW(), NOW()),
          (2, 'guest@example.com', 'x', 'Ian', 'Invitee', NOW(), NOW()),
          (3, 'ghost@example.com', 'x', 'Gone', 'Ghost', NOW(), NOW())
      SQL
      connection.execute(<<~SQL.squish)
        INSERT INTO events (id, name, description, status, user_id, created_at, updated_at)
        VALUES (1, 'Legacy', 'legacy event', FALSE, 1, NOW(), NOW())
      SQL
      connection.execute("INSERT INTO user_events (user_id, event_id, created_at, updated_at) VALUES (2, 1, NOW(), NOW()), (1, 1, NOW(), NOW())")
      connection.execute(<<~SQL.squish)
        INSERT INTO time_slots (user_id, event_id, start_time, created_at, updated_at) VALUES
          (1, 1, '2030-01-15 10:00:00', NOW(), NOW()),
          (2, 1, '2030-01-15 10:00:00', NOW(), NOW()),
          (3, 1, '2030-01-15 11:00:00', NOW(), NOW())
      SQL

      MIGRATIONS.each { |migration| migration.new.migrate(:up) }
    end
    MODELS.each(&:reset_column_information)

    rows = connection.select_all("SELECT role, email, user_id, responded_at IS NOT NULL AS replied FROM participants ORDER BY role, email").to_a
    assert_equal [
      { "role" => "guest", "email" => "guest@example.com", "user_id" => 2, "replied" => true },
      { "role" => "organizer", "email" => "org@example.com", "user_id" => 1, "replied" => true }
    ], rows
    assert_equal 2, connection.select_value("SELECT COUNT(*) FROM time_slots"), "the ghost's orphaned slot is deleted"
  ensure
    MODELS.each(&:reset_column_information)
  end

  private

  def connection
    ActiveRecord::Base.connection
  end
end
