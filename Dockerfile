FROM ruby:3.3-slim

# System dependencies needed for native gem extensions (sqlite3, etc.)
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential \
    libsqlite3-dev \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install gems first for better layer caching
COPY Gemfile debug-agent.gemspec ./
COPY lib/debug_agent/version.rb lib/debug_agent/version.rb
RUN bundle install

# Copy the rest of the application
COPY . .

EXPOSE 4567

CMD ["bundle", "exec", "ruby", "demo/app.rb"]
