# Development Dockerfile for the festival app.
# One image is reused by the web, css watcher and sidekiq services.
FROM ruby:3.3.12-slim

ENV RAILS_ENV=development \
    BUNDLE_PATH=/usr/local/bundle \
    LANG=C.UTF-8 \
    TZ=Etc/UTC

# System packages:
#   build-essential + libpq-dev  -> compile the native `pg` gem
#   postgresql-client            -> pg_isready / psql from inside the container
#   libyaml-dev                  -> psych (YAML) native build
#   git, curl                    -> tooling some gems shell out to
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
      postgresql-client \
      libyaml-dev \
      git \
      curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /rails

# Install gems first so this layer is cached until the Gemfile changes.
COPY Gemfile Gemfile.lock ./
RUN gem install bundler && bundle install

# Copy the app. In development this is overlaid by a bind mount (see
# docker-compose.yml), so live edits on the host are picked up immediately.
COPY . .

EXPOSE 3000

# Remove a stale server pid if a previous container left one behind, then boot.
CMD ["sh", "-c", "rm -f tmp/pids/server.pid && bin/rails server -b 0.0.0.0 -p 3000"]
