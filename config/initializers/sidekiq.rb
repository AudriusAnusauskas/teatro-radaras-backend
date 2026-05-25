require "sidekiq"

# Use Redis DB 1 in dev to isolate from other local apps that may default to DB 0.
# In production REDIS_URL will come from Railway environment.
REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379/1")

Sidekiq.configure_server do |config|
  config.redis = { url: REDIS_URL }
end

Sidekiq.configure_client do |config|
  config.redis = { url: REDIS_URL }
end
