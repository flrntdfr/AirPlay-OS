# frozen_string_literal: true

# The update button in the AirPlay card.
#   check  → compares the running shairport-sync with the latest GitHub release and caches the
#            answer (same thing ampberry-updates.timer does daily); a GET to GitHub, no privilege
#   status → the cached answer plus the state of the background job (the update itself goes
#            through the control API as the allow-listed update-shairport action)
class UpdatesController < ApplicationController
  def check
    render json: Ampberry::Updates.check
  end

  def status
    render json: Ampberry::Updates.status.merge("job" => AmpberryBridge.redeploy_state)
  end
end
