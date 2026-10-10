# frozen_string_literal: true

class HealthController < ActionController::API
  def show
    now = AirPlayOSBridge.now_playing
    render json: { "ok" => true, "version" => AirPlayOS::VERSION, "metadata" => !now["stale"], "time" => Time.now.utc.iso8601 }
  end
end
