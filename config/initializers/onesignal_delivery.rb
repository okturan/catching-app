require "onesignal_delivery"

ActiveSupport.on_load(:action_mailer) do
  add_delivery_method :onesignal, OnesignalDelivery
end
