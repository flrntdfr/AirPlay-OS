# frozen_string_literal: true

# "Check for updates" from the AirPlay card: compares the running shairport-sync with the latest
# GitHub release and caches the answer (same thing ampberry-updates.timer does daily). Runs as the
# UI user — a GET to GitHub, no privilege needed.
class UpdatesController < ApplicationController
  def check
    render json: Ampberry::Updates.check
  end
end
