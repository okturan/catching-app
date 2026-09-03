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
      starts_at: [ 18, 19, 20 ].map { |hour| tomorrow + hour.hours },
      invitee_emails: users.first(2).map(&:email)
    )
    organizer = event.organizer
    organizer.update_columns(link_opened_at: Time.current)
    puts "Organizer link: /p/#{organizer.issue_live_token!}"
    event.guests.each do |guest|
      guest.update!(user: User.find_by(email: guest.email))
      puts "Guest link for #{guest.email}: /p/#{guest.issue_live_token!}"
    end
  end

  [
    { name: "Movies", duration: 2, description: "Watch a favorite film together" },
    { name: "Gaming", duration: 1, description: "Play an online game together" },
    { name: "Karaoke", duration: 2, description: "Unleash your inner rockstar" }
  ].each do |attributes|
    event.activities.find_or_create_by!(attributes)
  end

  puts "Seeded #{User.count} users, #{Event.count} event, and #{Activity.count} activities."
end
