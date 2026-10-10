# frozen_string_literal: true

# AirPlay OS runtime library — the part of the appliance the Nix flake cannot express because it
# changes at runtime: settings → shairport-sync.conf, the firewall, Wi-Fi onboarding, the control
# API the web UI talks to, and the metadata daemon. Ruby stdlib only.
#
# Every filesystem location goes through AirPlayOS.path so the tests can relocate the whole tool
# with AIRPLAY_OS_ROOT (a prefix) without touching the real system.
module AirPlayOS
  VERSION = "0.2.0"

  PATHS = {
    etc: "/etc/airplay-os",
    defaults: "/etc/airplay-os/defaults.json",
    secrets: "/etc/airplay-os/secrets.json",
    actions: "/etc/airplay-os/actions.json",
    state: "/var/lib/airplay-os",
    settings: "/var/lib/airplay-os/settings.json",
    wifi_state: "/var/lib/airplay-os/wifi-state.json",
    ui_secret: "/var/lib/airplay-os/ui-secret",
    need_reboot: "/var/lib/airplay-os/need-reboot",
    log: "/var/log/airplay-os",
    run_dir: "/run/airplay-os",
    now_playing: "/run/airplay-os/now-playing.json",
    updates: "/run/airplay-os/updates.json",
    control_socket: "/run/airplay-os-control.sock",
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
    flake: "/opt/airplay-os",
    release: "/etc/airplay-os/release",
    device: "/etc/airplay-os/device.json", # docs/devices/<id>.json, shipped by the flake
    update_flake: "/var/lib/airplay-os/shairport-update", # written by `redeploy run --update-shairport`
    system_path: "/etc/airplay-os/system-path",
    system_manager_path: "/etc/airplay-os/system-manager-path",
    redeploy_log: "/var/log/airplay-os/redeploy.log",
    redeploy_state: "/var/log/airplay-os/redeploy.json",
    applog: "/var/log/airplay-os.log"
  }.freeze

  class Error < StandardError; end

  # What the tools assume when /etc/airplay-os/device.json is missing (tests, the Mac preview,
  # a box provisioned before device definitions existed): the original AirPlayOS.
  DEFAULT_DEVICE = {
    "id" => "ampberry", "hostname" => "ampberry", "pretty_name" => "Ampberry", "description" => "AirPlay 2 speaker",
    "overlay" => "hifiberry-dacplus-std", "wifi" => true, "bluetooth" => false, "primary_interface" => "wlan0"
  }.freeze

  # The device this box is (docs/devices/<id>.json as shipped to /etc/airplay-os/device.json).
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
    ENV.fetch("AIRPLAY_OS_ROOT", "")
  end

  def self.path(key)
    raise ArgumentError, "AirPlayOS.path: unknown key #{key.inspect}" unless PATHS.key?(key)

    root + PATHS.fetch(key)
  end

  # Upstream versions the flake pins (informational for the tools; the flake is the source).
  def self.pins
    { shairport_sync: "5.5.2", nqptp: "1.2.8" }
  end

  autoload :Run, "airplay_os/run"
  autoload :Log, "airplay_os/log"
  autoload :Config, "airplay_os/config"
  autoload :Settings, "airplay_os/settings"
  autoload :Wifi, "airplay_os/wifi"
  autoload :System, "airplay_os/system"
  autoload :Metadata, "airplay_os/metadata"
  autoload :MetadataDaemon, "airplay_os/metadata_daemon"
  autoload :Actions, "airplay_os/actions"
  autoload :Control, "airplay_os/control"
  autoload :Provision, "airplay_os/provision"
  autoload :Redeploy, "airplay_os/redeploy"
  autoload :LogAggregator, "airplay_os/log_aggregator"
  autoload :Remote, "airplay_os/remote"
  autoload :Health, "airplay_os/health"
  autoload :Updates, "airplay_os/updates"
  autoload :Network, "airplay_os/network"
end
