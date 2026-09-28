module TimeSlotParams
  private

  def parsed_time_slots(slot_minutes:)
    TimeSlot.parse(params.expect(time_slots: [ :time_slot_array ])[:time_slot_array], slot_minutes:)
  end
end
