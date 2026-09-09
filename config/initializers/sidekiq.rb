# Sidekiq reads REDIS_URL from the environment by default; we set it explicitly
# so both the client (web) and the server (sidekiq container) agree.
redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
