# frozen_string_literal: true

require "json"

module AirPlayOS
  # Wi-Fi status, onboarding hotspot and network joining on top of NetworkManager (nmcli).
  #
  # State machine (ensure, run by airplay-os-wifi-fallback.timer every few minutes):
  #   connected            → hotspot down, miss counter reset
  #   not connected ×2     → (no eth0 carrier) bring the "AirPlay-OS-setup" hotspot up
  #   hotspot older than   → bring it down so NetworkManager can retry the known networks;
  #     HOTSPOT_MAX_AGE      if that fails twice again, the hotspot returns
  #
  # The hotspot is WPA2 (setup_psk from /etc/airplay-os/secrets.json), 2.4 GHz, NM "shared" mode
  # (NM runs dnsmasq; the flake's dnsmasq-shared.d/airplay-os-captive.conf answers every name with
  # 10.42.0.1 so the phone's captive-portal sheet opens the setup page).
  #
  # connect adds a new profile and only tears the hotspot down for the attempt; on failure the new
  # profile is deleted and the hotspot restored. Existing profiles are never deleted.
  module Wifi
    HOTSPOT_NAME = "AirPlay-OS-setup"
    HOTSPOT_SSID = "AirPlay-OS-setup"
    IFACE = "wlan0"
    MISSES_FOR_HOTSPOT = 2
    HOTSPOT_MAX_AGE = 15 * 60
    CONNECT_TIMEOUT = 45

    class << self
      # ---- nmcli --terse parsing ------------------------------------------------------------

      # nmcli escapes ':' as '\:' and '\' as '\\' in terse output.
      def split_terse(line)
        line.chomp.split(/(?<!\\):/, -1).map { |f| f.gsub(/\\(.)/, '\1') }
      end

      # ---- queries -----------------------------------------------------------------------------

      # Visible networks, strongest first, one entry per SSID.
      def scan(text: nil, rescan: "yes")
        text ||= Run.capture("nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY,BSSID,CHAN,FREQ,IN-USE",
                             "device", "wifi", "list", "--rescan", rescan, quiet: true, timeout: 60)
        best = {}
        text.each_line do |line|
          next if line.strip.empty?

          ssid, signal, security, bssid, chan, freq, in_use = split_terse(line)
          next if ssid.nil? || ssid.empty?

          n = { "ssid" => ssid, "signal" => signal.to_i, "security" => security.to_s, "bssid" => bssid.to_s,
                "chan" => chan.to_s, "freq" => freq.to_s, "in_use" => in_use == "*",
                "open" => security.to_s.empty? || security == "--" }
          best[ssid] = n if !best[ssid] || n["in_use"] || n["signal"] > best[ssid]["signal"]
        end
        best.values.sort_by { |n| [n["in_use"] ? 0 : 1, -n["signal"], n["ssid"]] }
      end

      def profiles(text: nil)
        text ||= Run.capture("nmcli", "-t", "-f", "NAME,UUID,TYPE,DEVICE,ACTIVE,AUTOCONNECT", "con", "show", quiet: true)
        text.each_line.filter_map do |line|
          next if line.strip.empty?

          name, uuid, type, device, active, auto = split_terse(line)
          { "name" => name, "uuid" => uuid, "type" => type, "device" => device.to_s,
            "active" => active == "yes", "autoconnect" => auto == "yes" }
        end
      end

      def profile_exists?(name, text: nil) = profiles(text: text).any? { |p| p["name"] == name }

      def hotspot_active?(text: nil) = profiles(text: text).any? { |p| p["name"] == HOTSPOT_NAME && p["active"] }

      # Overall status used by the UI, the timer and the firewall.
      def status(device_text: nil, route_text: nil, ip4: :detect, profiles_text: nil, eth_carrier: nil)
        device_text ||= Run.capture("nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status", quiet: true)
        devices = {}
        device_text.each_line do |line|
          dev, type, state, conn = split_terse(line)
          next if dev.nil? || dev.empty?

          devices[dev] = { "type" => type, "state" => state.to_s, "connection" => conn.to_s }
        end
        wlan = devices[IFACE] || { "state" => "missing", "connection" => "" }
        eth = devices["eth0"] || devices["end0"] || { "state" => "missing", "connection" => "" }

        route_text ||= Run.capture("ip", "-4", "route", "show", "default", quiet: true)
        gw, gw_dev = route_text.match(/^default via (\S+) dev (\S+)/)&.captures
        hotspot = profiles_text ? hotspot_active?(text: profiles_text) : hotspot_active?
        ip4 = ip4_of(IFACE) if ip4 == :detect
        eth_carrier = carrier?("eth0") if eth_carrier.nil?
        wifi_connected = wlan["state"].start_with?("connected") && !hotspot

        { "wifi_state" => wlan["state"], "connection" => wlan["connection"], "wifi_connected" => wifi_connected,
          "hotspot" => hotspot, "ip4" => ip4.to_s, "gateway" => gw.to_s, "gateway_dev" => gw_dev.to_s,
          "online" => !gw.nil? && !hotspot, "eth_state" => eth["state"], "eth_carrier" => eth_carrier ? true : false }
      end

      # ---- hotspot ----------------------------------------------------------------------------

      def ensure_hotspot_profile(psk)
        raise AirPlayOS::Error, "hotspot PSK must be 8..63 characters" unless psk.is_a?(String) && psk.length.between?(8, 63)
        return false if profile_exists?(HOTSPOT_NAME)

        Run.run("nmcli", "con", "add", "type", "wifi", "ifname", IFACE, "con-name", HOTSPOT_NAME,
                "autoconnect", "no", "ssid", HOTSPOT_SSID,
                "802-11-wireless.mode", "ap", "802-11-wireless.band", "bg",
                "ipv4.method", "shared", "ipv6.method", "disabled",
                "wifi-sec.key-mgmt", "wpa-psk", "wifi-sec.psk", psk,
                "802-11-wireless-security.proto", "rsn", "802-11-wireless-security.pairwise", "ccmp", timeout: 30)
        true
      end

      def hotspot_on(psk: nil)
        ensure_hotspot_profile(psk || setup_psk)
        return false if hotspot_active?

        Run.run("nmcli", "--wait", "30", "con", "up", "id", HOTSPOT_NAME, timeout: 60)
        save_state("hotspot_since" => Time.now.to_i, "misses" => 0)
        true
      end

      def hotspot_off
        return false unless hotspot_active?

        Run.run("nmcli", "con", "down", "id", HOTSPOT_NAME, ok: [0, 10], timeout: 60)
        save_state(load_state.merge("hotspot_since" => 0))
        true
      end

      # ---- joining a network -----------------------------------------------------------------

      def connect(ssid, psk, no_boot_config: false)
        raise AirPlayOS::Error, "SSID must be 1..32 characters" unless ssid.is_a?(String) && ssid.length.between?(1, 32)
        raise AirPlayOS::Error, "SSID contains control characters" if ssid.match?(/[\x00-\x1f]/)

        open = psk.nil? || psk.empty?
        valid_psk = psk.to_s.length.between?(8, 63) || psk.to_s.match?(/\A\h{64}\z/)
        raise AirPlayOS::Error, "passphrase must be 8..63 characters or a 64-digit hex PSK (empty for an open network)" if !open && !valid_psk

        had_hotspot = hotspot_active?
        existed = profile_exists?(ssid)
        security = open ? ["wifi-sec.key-mgmt", "none"] : ["wifi-sec.key-mgmt", "wpa-psk", "wifi-sec.psk", psk]
        if existed
          Run.run("nmcli", "con", "modify", "id", ssid, "connection.autoconnect", "yes", *security, timeout: 30)
        else
          Run.run("nmcli", "con", "add", "type", "wifi", "ifname", IFACE, "con-name", ssid, "ssid", ssid,
                  "connection.autoconnect", "yes", *(open ? [] : security), timeout: 30)
        end
        hotspot_off if had_hotspot

        r = Run.try_run("nmcli", "--wait", CONNECT_TIMEOUT.to_s, "con", "up", "id", ssid, timeout: CONNECT_TIMEOUT + 15)
        unless r.status.zero?
          Run.try_run("nmcli", "con", "delete", "id", ssid, timeout: 30) unless existed
          hotspot_on if had_hotspot
          raise AirPlayOS::Error, "could not join '#{ssid}': #{r.err.strip}"
        end
        save_state("hotspot_since" => 0, "misses" => 0)
        write_network_config(ssid, open ? nil : psk) unless no_boot_config
        status
      end

      # ---- the periodic state machine --------------------------------------------------------

      def ensure(now: Time.now.to_i)
        st = status
        state = load_state
        if st["wifi_connected"] || st["eth_carrier"]
          action = "connected"
          if st["hotspot"]
            hotspot_off
            action = "hotspot-off"
          end
          save_state("hotspot_since" => 0, "misses" => 0)
          return { "action" => action, "status" => st }
        end
        if st["hotspot"]
          age = now - (state["hotspot_since"].to_i.nonzero? || now)
          if age >= HOTSPOT_MAX_AGE
            hotspot_off
            save_state("hotspot_since" => 0, "misses" => 0)
            return { "action" => "hotspot-expired", "status" => st }
          end
          return { "action" => "hotspot-waiting", "status" => st }
        end
        misses = state["misses"].to_i + 1
        if misses >= MISSES_FOR_HOTSPOT
          hotspot_on
          return { "action" => "hotspot-on", "status" => status }
        end
        save_state(state.merge("misses" => misses))
        { "action" => "waiting", "misses" => misses, "status" => st }
      end

      # ---- /boot/firmware/network-config (netplan v2) ------------------------------------------

      def render_network_config(ssid, psk, country: "DE")
        auth = psk && !psk.empty? ? "          password: #{yaml_q(psk)}\n" : "          {}\n"
        <<~YAML
          network:
            version: 2
            ethernets:
              eth0:
                dhcp4: true
                dhcp6: true
                optional: true
            wifis:
              wlan0:
                dhcp4: true
                regulatory-domain: "#{country}"
                access-points:
                  #{yaml_q(ssid)}:
          #{auth}      optional: true
        YAML
      end

      # Returns true when the file was (re)written.
      def write_network_config(ssid, psk, country: "DE")
        path = AirPlayOS.path(:network_config)
        yaml = render_network_config(ssid, psk, country: country)
        if File.exist?(path)
          old = File.read(path)
          return false if old == yaml

          File.write("#{path}.bak", old)
        end
        File.write("#{path}.tmp", yaml)
        File.rename("#{path}.tmp", path)
        true
      end

      private

      def yaml_q(s) = %("#{s.gsub(/[\\"]/) { "\\#{$&}" }}")

      def ip4_of(iface)
        r = Run.try_run("ip", "-4", "-o", "addr", "show", "dev", iface, quiet: true, read_only: true)
        return nil unless r.status.zero?

        r.out[%r{\binet (\d+\.\d+\.\d+\.\d+/\d+)}, 1]
      end

      def carrier?(iface)
        # through AirPlayOS.root so tests (and unsandboxed builds) never read the build host's interfaces
        File.read(File.join(AirPlayOS.root, "/sys/class/net/#{iface}/carrier")).include?("1")
      rescue SystemCallError
        false
      end

      def setup_psk
        path = AirPlayOS.path(:secrets)
        raise AirPlayOS::Error, "no hotspot PSK configured (#{path} missing)" unless File.exist?(path)

        Config.load_json(path).fetch("setup_psk") { raise AirPlayOS::Error, "setup_psk missing in #{path}" }
      end

      def load_state
        p = AirPlayOS.path(:wifi_state)
        File.exist?(p) ? Config.load_json(p) : {}
      end

      def save_state(state) = Config.save_json_atomic(AirPlayOS.path(:wifi_state), state)
    end
  end
end
