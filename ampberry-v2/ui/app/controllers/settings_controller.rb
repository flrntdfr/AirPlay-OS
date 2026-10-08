# frozen_string_literal: true

class SettingsController < ApplicationController
  # Inside the Settings overlay the page is a Turbo Frame: no layout, just the frame.
  layout -> { turbo_frame_request? ? false : "application" }

  # What the page offers, ranked by how often it is useful. Everything else in the allow-list
  # (clean-reboot, wifi-*, settings-*) stays reachable via `sudo ampberry action run` and the API.
  GROUPS = [
    { title: "Maintenance",
      ids: %w[restart-airplay] },
    { title: "System",
      ids: %w[reboot redeploy] }
  ].freeze

  def show
    res = AmpberryBridge.call("settings-show")
    catalogue = AmpberryBridge.actions.index_by { |a| a["id"] }
    groups = GROUPS.map { |g| g.merge(actions: g[:ids].filter_map { |id| catalogue[id] }) }
    render Views::Settings::Show.new(
      settings: res.dig("result", "settings") || {},
      schema: AmpberryBridge.settings_schema,
      groups: groups,
      error: (res["error"] unless res["ok"]),
      flake: { "build" => release["BUILD"], "version" => release["FLAKE_VERSION"], "path" => AmpberryBridge.flake_path },
      notice: flash[:notice],
      alert: flash[:alert],
      embedded: turbo_frame_request?
    )
  end

  def update
    schema = AmpberryBridge.settings_schema
    permitted = params.fetch(:settings, ActionController::Parameters.new).permit(*schema.keys).to_h
    permitted.each do |k, v|
      next unless schema[k][:type] == :number && v.is_a?(String)

      permitted[k] = Float(v)
    rescue ArgumentError
      # left as-is; the control side reports the validation problem
    end
    res = AmpberryBridge.call("settings-apply", { "settings" => permitted })
    flash[res["ok"] ? :notice : :alert] = res["ok"] ? "Settings applied. AirPlay restarted." : res["error"]
    redirect_to settings_path # Turbo follows it inside the frame
  end
end
