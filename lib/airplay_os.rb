# frozen_string_literal: true

# Ampberry runtime library — the part of the appliance the Nix flake cannot express because it
# changes at runtime: settings → shairport-sync.conf, the firewall, Wi-Fi onboarding, the control
# API the web UI talks to, and the metadata daemon. Ruby stdlib only.
#
# Every filesystem location goes through Ampberry.path so the tests can relocate the whole tool
# with AMPBERRY_ROOT (a prefix) without touching the real system.
module Ampberry
  VERSION = "0.2.0"

  PATHS = {
    etc: "/etc/ampberry",
    defaults: "/etc/ampberry/defaults.json",
    secrets: "/etc/ampberry/secrets.json",
    actions: "/etc/ampberry/actions.json",
    state: "/var/lib/ampberry",
    settings: "/var/lib/ampberry/settings.json",
    wifi_state: "/var/lib/ampberry/wifi-state.json",
    ui_secret: "/var/lib/ampberry/ui-secret",
    need_reboot: "/var/lib/ampberry/need-reboot",
    log: "/var/log/ampberry",
    run_dir: "/run/ampberry",
    now_playing: "/run/ampberry/now-playing.json",
    updates: "/run/ampberry/updates.json",
    control_socket: "/run/ampberry-control.sock",
    boot: "/boot/firmware",
    config_txt: "/boot/firmware/config.txt",
    network_config: "/boot/firmware/network-config",
    shairport_conf: "/etc/shairport-sync.conf",
    metadata_pipe: "/run/shairport-sync/metadata",
    avahi_conf: "/etc/avahi/avahi-daemon.conf",
    hifiberry_list: "/etc/apt/sources.list.d/hifiberry.list",
    hifiberry_key: "/usr/share/keyrings/hifiberry-archive-keyring.gpg",
    hifiberry_user: "/etc/hifiberry.user",
    pi_home: "/home/pi",
    flake: "/opt/ampberry",
    release: "/etc/ampberry/release",
    device: "/etc/ampberry/device.json", # devices/<id>.json, shipped by the flake
    update_flake: "/var/lib/ampberry/shairport-update", # written by `redeploy run --update-shairport`
    system_path: "/etc/ampberry/system-path",
    system_manager_path: "/etc/ampberry/system-manager-path",
    redeploy_log: "/var/log/ampberry/redeploy.log",
    redeploy_state: "/var/log/ampberry/redeploy.json",
    applog: "/var/log/ampberry.log"
  }.freeze

  class Error < StandardError; end

  # What the tools assume when /etc/ampberry/device.json is missing (tests, the Mac preview,
  # a box provisioned before device definitions existed): the original Ampberry.
  DEFAULT_DEVICE = {
    "id" => "ampberry", "hostname" => "ampberry", "pretty_name" => "Ampberry", "description" => "AirPlay 2 speaker",
    "overlay" => "hifiberry-dacplus-std", "wifi" => true, "bluetooth" => false, "primary_interface" => "wlan0"
  }.freeze

  # The device this box is (devices/<id>.json as shipped to /etc/ampberry/device.json).
  def self.device
    @device ||= begin
      require "json"
      DEFAULT_DEVICE.merge(JSON.parse(File.read(path(:device))))
    rescue SystemCallError, JSON::ParserError
      DEFAULT_DEVICE.dup
    end
  end

  def self.reset_device! = @device = nil

  def self.root
    ENV.fetch("AMPBERRY_ROOT", "")
  end

  def self.path(key)
    raise ArgumentError, "Ampberry.path: unknown key #{key.inspect}" unless PATHS.key?(key)

    root + PATHS.fetch(key)
  end

  # Upstream versions the flake pins (informational for the tools; the flake is the source).
  def self.pins
    { shairport_sync: "5.5.2", nqptp: "1.2.8" }
  end

  autoload :Run, "ampberry/run"
  autoload :Log, "ampberry/log"
  autoload :Config, "ampberry/config"
  autoload :Settings, "ampberry/settings"
  autoload :Wifi, "ampberry/wifi"
  autoload :System, "ampberry/system"
  autoload :Metadata, "ampberry/metadata"
  autoload :MetadataDaemon, "ampberry/metadata_daemon"
  autoload :Actions, "ampberry/actions"
  autoload :Control, "ampberry/control"
  autoload :Provision, "ampberry/provision"
  autoload :Redeploy, "ampberry/redeploy"
  autoload :LogAggregator, "ampberry/log_aggregator"
  autoload :Remote, "ampberry/remote"
  autoload :Health, "ampberry/health"
  autoload :Updates, "ampberry/updates"
  autoload :Network, "ampberry/network"
end
