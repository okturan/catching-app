class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAILER_FROM") }
  layout "mailer"
end
