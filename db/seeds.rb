# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)
Event.create(name: 'meeting', user_id: '1')
Event.create(name: 'meeting2', user_id: '1')

netflix = { name: 'Netflix', duration: 12, description: 'so much fun', event_id: 1 }
gaming = { name: 'Gaming', duration: 1, description: 'fun times', event_id: 1 }

[netflix, gaming].each do |attributes|
  activity = Activity.create!(attributes)
  puts "created #{activity.name}"
end
