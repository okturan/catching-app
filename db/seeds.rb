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

  organizer = users.last
  event = organizer.events.find_or_initialize_by(name: "Movie night")
  event.update!(description: "Pick a time to watch a movie together")
  event.invited_users = users.first(2)

  [
    { name: "Movies", duration: 2, description: "Watch a favorite film together" },
    { name: "Gaming", duration: 1, description: "Play an online game together" },
    { name: "Karaoke", duration: 2, description: "Unleash your inner rockstar" }
  ].each do |attributes|
    event.activities.find_or_create_by!(attributes)
  end

  puts "Seeded #{User.count} users, #{Event.count} event, and #{Activity.count} activities."
end
