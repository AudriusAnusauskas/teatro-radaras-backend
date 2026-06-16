source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.2.3", ">= 7.2.3.1"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use Redis adapter to run Action Cable in production
# gem "redis", ">= 4.0.1"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
# gem "rack-cors"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

# --- Background jobs & cache
gem "sidekiq", "~> 7.3"
gem "redis", "~> 5.3"

# --- Scraping
gem "nokogiri", "~> 1.17"
gem "ferrum", "~> 0.16"

# --- Auth
gem "devise", "~> 4.9"
gem "omniauth", "~> 2.1"
gem "omniauth-google-oauth2", "~> 1.2"

# --- API plumbing
gem "rack-cors", "~> 2.0"
gem "friendly_id", "~> 5.5"

# --- HTTP klientai
gem "faraday", "~> 2.14"
gem "faraday-retry", "~> 2.2"

# --- ENV
gem "dotenv-rails", groups: %i[development test]



gem "rspec-rails", "~> 8.0", :groups => [:development, :test]
gem "factory_bot_rails", "~> 6.5", :groups => [:development, :test]
gem "faker", "~> 3.8", :groups => [:development, :test]

gem "sidekiq-scheduler", "~> 6.0"

# Sidekiq 7.3.x requires connection_pool < 3.0
gem "connection_pool", "~> 2.5"
