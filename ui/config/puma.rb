# frozen_string_literal: true

# One process, a couple of threads: a 1 GB Pi 3 serving one household.
threads 1, 3
workers 0
port ENV.fetch("PORT", 80)
environment ENV.fetch("RAILS_ENV", "production")
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
