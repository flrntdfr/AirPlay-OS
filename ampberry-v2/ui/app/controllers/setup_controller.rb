# frozen_string_literal: true

class SetupController < ApplicationController
  def show
    status = AmpberryBridge.call("wifi-status")
    render_page(status: status.dig("result", "status") || {}, networks: [], error: (status["error"] unless status["ok"]))
  end

  def scan
    res = AmpberryBridge.call("wifi-scan")
    status = AmpberryBridge.call("wifi-status").dig("result", "status") || {}
    render_page(status: status, networks: res.dig("result", "networks") || [], error: (res["error"] unless res["ok"]))
  end

  def connect
    res = AmpberryBridge.call("wifi-connect", { "ssid" => params[:ssid].to_s, "psk" => params[:psk].to_s })
    if res["ok"]
      flash[:notice] = "Joined “#{params[:ssid]}”. Reconnect your phone to the same network and open http://ampberry.local/."
    else
      flash[:alert] = res["error"]
    end
    redirect_to setup_path
  end

  private

  def render_page(status:, networks:, error:)
    render Views::Setup::Show.new(status: status, networks: networks, error: error)
  end
end
