if !Rails.env.development?
  warn "Demo seeds are only available in development."
else
  password = ENV.fetch("SEED_PASSWORD", "development-password")

  users = [
    { email: "ege@example.test", first_name: "Ege", last_name: "Çakmak" },
    { email: "sedef@example.test", first_name: "Sedef", last_name: "Çakmak" },
    { email: "okan@example.test", first_name: "Okan", last_name: "Erturan" }
  ].map do |attributes|
    User.find_or_initialize_by(email: attributes.fetch(:email)).tap do |user|
      user.assign_attributes(attributes.merge(password: password))
      user.save!
    end
  end

  organizer_user = users.last
  event = Event.find_by(name: "Movie night")

  unless event
    tomorrow = 1.day.from_now.utc.beginning_of_day
    event = Event.plan!(
      attributes: { name: "Movie night", description: "Pick a time to watch a movie together", slot_minutes: 60, time_zone: "UTC" },
      organizer: { email: organizer_user.email, name: organizer_user.full_name, user: organizer_user },
      starts_at: [ 18, 19, 20 ].map { tomorrow + it.hours }
    )
    event.organizer.update_columns(link_opened_at: Time.current)
    puts "Organizer link: /p/#{event.organizer.issue_live_token!}"
    users.first(2).each do |user|
      guest = event.participants.guest.create!(email: user.email, user:)
      puts "Guest link for #{guest.email}: /p/#{guest.issue_live_token!}"
    end
  end

  [
    { name: "Pizza first", duration_minutes: 30, position: 0 },
    { name: "The movie", duration_minutes: 120, position: 1 }
  ].each do |attributes|
    event.plan_items.find_or_create_by!(attributes)
  end

  puts "Seeded #{User.count} users, #{Event.count} event, and a plan of #{PlanItem.count} items."
end
