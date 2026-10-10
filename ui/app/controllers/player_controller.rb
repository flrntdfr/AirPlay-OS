# frozen_string_literal: true

class PlayerController < ApplicationController
  def index
    render Views::Player::Index.new(now: AmpberryBridge.now_playing, release: release)
  end

  def now_playing
    render json: AmpberryBridge.now_playing
  end

  # Play/pause the sender. Unprivileged: an HTTP GET to the phone's DACP service with the
  # session token from the metadata (Ampberry::Remote).
  def toggle
    res = Ampberry::Remote.command("playpause", AmpberryBridge.now_playing)
    render json: { "ok" => true }.merge(res)
  rescue Ampberry::Error, SystemCallError, IOError, Timeout::Error => e
    render json: { "ok" => false, "error" => e.message }, status: :unprocessable_entity
  end

  def cover
    path = AmpberryBridge.cover_path("#{params[:file]}")
    return head :not_found unless path

    expires_in 1.year, public: false
    mime = { ".jpg" => "image/jpeg", ".png" => "image/png" }.fetch(File.extname(path), "application/octet-stream")
    send_file path, type: mime, disposition: "inline"
  end
end
