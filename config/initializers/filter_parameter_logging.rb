Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]
