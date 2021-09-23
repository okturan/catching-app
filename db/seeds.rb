# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)
Activity.destroy_all
Event.destroy_all
User.destroy_all

user1 = User.create(email: "okan@test.com", password: "123456")

event1 = Event.create(name: 'meeting', user: user1)
event2 = Event.create(name: 'meeting2', user: user1)


netflix = { name: 'Netflix', duration: 12, description: 'so much fun', event: event1 }
gaming = { name: 'Gaming', duration: 1, description: 'fun times', event: event1 }

[netflix, gaming].each do |attributes|
  activity = Activity.create!(attributes)
  puts "created #{activity.name}"
end
