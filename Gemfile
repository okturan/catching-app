source "https://rubygems.org"

ruby "4.0.5"

gem "rails", "~> 8.1.3"

# Runtime and persistence
gem "bootsnap", require: false
gem "pg", "~> 1.6"
gem "propshaft"
gem "puma", ">= 7.0"
gem "thruster", require: false

# JavaScript and CSS
gem "cssbundling-rails"
gem "jsbundling-rails"
gem "turbo-rails"

# Application dependencies
gem "devise"
gem "simple_form"
gem "tzinfo-data", platforms: %i[windows jruby]

group :development, :test do
  gem "brakeman", require: false
  gem "bundler-audit", require: false
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "dotenv-rails"
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
