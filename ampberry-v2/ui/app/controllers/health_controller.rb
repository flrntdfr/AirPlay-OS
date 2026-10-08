# frozen_string_literal: true

class HealthController < ActionController::API
  def show
    now = AmpberryBridge.now_playing
    render json: { "ok" => true, "version" => Ampberry::VERSION, "metadata" => !now["stale"], "time" => Time.now.utc.iso8601 }
  end
end
