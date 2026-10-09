# frozen_string_literal: true

# Everything the UI knows about the appliance comes through here:
#   * now-playing state: files written by the metadata daemon under /run/ampberry
#   * actions/settings/Wi-Fi: the root-side control socket (allow-listed actions only)
#   * the action catalogue and release info: root-owned, world-readable files
module AmpberryBridge
  module_function

  def control
    Ampberry::Control::Client.new(socket_path: Rails.configuration.x.control_socket)
  end

  # Never lets a control-side problem take a page down: the pages show the error instead.
  def call(action, params = {})
    control.call(action, params)
  rescue StandardError => e
    Rails.logger.warn("control #{action}: #{e.class}: #{e.message}")
    { "ok" => false, "action" => action, "error" => "control: #{e.message}" }
  end

  def now_playing
    path = File.join(Rails.configuration.x.run_dir, "now-playing.json")
    JSON.parse(File.read(path))
  rescue Errno::ENOENT, JSON::ParserError
    { "playing" => false, "active" => false, "title" => "", "artist" => "", "album" => "", "stale" => true }
  end

  def cover_path(file)
    return nil unless file.match?(/\Acover-[0-9a-f]{40}\.(?:jpg|png|bin)\z/)

    path = File.join(Rails.configuration.x.run_dir, file)
    File.file?(path) ? path : nil
  end

  def actions
    Ampberry::Actions.list(path: Rails.configuration.x.actions_file)
  rescue Ampberry::Error => e
    Rails.logger.warn("actions catalogue unavailable: #{e.message}")
    Ampberry::Actions.list(path: "/nonexistent")
  end

  def settings_schema = Ampberry::Config.settings_schema

  def release
    File.readlines(Rails.configuration.x.release_file, chomp: true).each_with_object({}) do |line, h|
      k, v = line.split("=", 2)
      h[k] = v.to_s.delete_prefix('"').delete_suffix('"') if k && v
    end
  rescue Errno::ENOENT
    { "NAME" => "Ampberry" }
  end

  # The flake source the running system was built from (/opt/ampberry → the Nix store).
  def flake_path
    File.readlink(Rails.configuration.x.flake_link)
  rescue SystemCallError
    nil
  end

  # The background job (Redeploy / Update): its world-readable state file.
  def redeploy_state
    st = JSON.parse(File.read(Ampberry.path(:redeploy_state)))
    st.slice("state", "kind", "started_at", "finished_at", "error")
  rescue Errno::ENOENT, JSON::ParserError
    { "state" => "idle" }
  end

  # The hardware address of the network interface (Wi‑Fi first, then Ethernet), from /sys;
  # nil when neither exists (the build sandbox, the Mac).
  def mac_address
    %w[wlan0 eth0].each do |iface|
      mac = File.read(File.join(Ampberry.root, "/sys/class/net/#{iface}/address")).strip
      return mac if mac.match?(/\A(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\z/i) && mac != "00:00:00:00:00:00"
    rescue SystemCallError
      next
    end
    nil
  end

  # The receiver's AirPlay name, from the rendered (world-readable) shairport-sync.conf — the
  # settings store itself is root-only, and asking the control socket on every page load would
  # log an action each time. nil when the file is missing or has no name.
  def airplay_name
    File.foreach(Rails.configuration.x.shairport_conf) do |line|
      m = line.match(/\A\s*name\s*=\s*"((?:[^"\\]|\\.)*)"\s*;/)
      return m[1].gsub(/\\(.)/, '\1') if m
    end
    nil
  rescue SystemCallError
    nil
  end
end
