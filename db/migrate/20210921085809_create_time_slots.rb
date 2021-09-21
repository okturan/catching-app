class CreateTimeSlots < ActiveRecord::Migration[6.0]
  def change
    create_table :time_slots do |t|
      t.references :user, null: false, foreign_key: true
      t.references :event, null: false, foreign_key: true
      t.datetime :start_time
      t.datetime :end_time

      t.timestamps
    end
  end
end
