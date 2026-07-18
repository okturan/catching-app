#!/usr/bin/env ruby

def assert(condition, message)
  raise message unless condition
end

root = File.expand_path('..', __dir__)
events_controller = File.read(File.join(root, 'app/controllers/events_controller.rb'))
time_slots_controller = File.read(File.join(root, 'app/controllers/time_slots_controller.rb'))
user = File.read(File.join(root, 'app/models/user.rb'))
event = File.read(File.join(root, 'app/models/event.rb'))
routes = File.read(File.join(root, 'config/routes.rb'))
readme = File.read(File.join(root, 'README.md'))

assert(events_controller.include?('before_action :set_accessible_event, only: [ :show ]'), 'Event show must use an access-scoped lookup')
assert(events_controller.include?('before_action :set_owned_event, only: [ :update ]'), 'Event update must use an owner-scoped lookup')
assert(events_controller.include?('@event = hosted.or(invited).find(params[:id])'), 'Event show must be limited to hosts and invitees')
assert(events_controller.include?('@event = current_user.events.find(params[:id])'), 'Final scheduling must be limited to the host')
assert(time_slots_controller.include?('@event = current_user.invited_events.find(my_params[:event_id])'), 'Availability submission must be limited to invited users')

%w[events time_slots user_events].each do |association|
  assert(user.include?("has_many :#{association}, dependent: :destroy"), "User #{association} must be cleaned on account deletion")
end
%w[time_slots user_events activities].each do |association|
  assert(event.include?("has_many :#{association}, dependent: :destroy"), "Event #{association} must be cleaned on event deletion")
end

assert(!routes.include?(':edit, :update'), 'The unimplemented event edit route must remain absent')
assert(readme.include?('must not be exposed or deployed'), 'README must retain the legacy dependency warning')
assert(readme.include?('three-person Le Wagon project'), 'README must retain the collaboration boundary')

puts 'Archive authorization contract passed'
