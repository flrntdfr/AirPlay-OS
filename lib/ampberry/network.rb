# frozen_string_literal: true

module Ampberry
  # The two network interfaces as the Settings pane's Network card shows them, on top of
  # NetworkManager (nmcli):
  #   status            → { "wlan0" => { iface, kind, label, present, state, connected, enabled,
  #                          ip4, ssid, connection, carrier }, "eth0" => { … } }   (any user)
  #   set(iface, on)    → root; refuses to switch off the only connected interface
  #   may_disable?      → the rule the switch follows: only when the other one is connected
  # "enabled" means: the Wi‑Fi radio is on (`nmcli radio wifi`, NetworkManager keeps it across
  # reboots) / Ethernet may autoconnect (`nmcli device set eth0 autoconnect` + connect or
  # disconnect — forgotten at the next reboot, so a cable always works again after one).
  module Network
    IFACES = { "wlan0" => "wifi", "eth0" => "ethernet" }.freeze
    LABELS = { "wifi" => "Wi‑Fi", "ethernet" => "Ethernet" }.freeze

    class << self
      def status(device_text: nil, radio_text: nil, wifi_text: nil)
        device_text ||= Run.capture("nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status", quiet: true)
        radio_text ||= Run.capture("nmcli", "-t", "radio", "wifi", quiet: true)
        devices = {}
        device_text.each_line do |line|
          dev, type, state, conn = Wifi.split_terse(line)
          devices[dev] = { "type" => type.to_s, "state" => state.to_s, "connection" => conn.to_s } if dev && !dev.empty?
        end
        wifi_on = radio_text.strip == "enabled"
        IFACES.to_h do |iface, kind|
          d = devices[iface]
          state = d ? d["state"].sub(/ .*\z/, "") : "absent" # "connected (externally)" → connected
          connected = state == "connected" && !(kind == "wifi" && d["connection"] == Wifi::HOTSPOT_NAME)
          autoconnect, ip4 = d ? details(iface) : [false, nil]
          s = { "iface" => iface, "kind" => kind, "label" => LABELS[kind], "present" => !d.nil?, "state" => state,
                "connected" => connected, "enabled" => (kind == "wifi" ? wifi_on : autoconnect),
                "ip4" => (connected ? ip4 : nil), "connection" => (d ? d["connection"] : "") }
          s["ssid"] = active_ssid(text: wifi_text) if kind == "wifi"
          s["carrier"] = carrier?(iface) if kind == "ethernet"
          [iface, s]
        end
      end

      # One word for the row.
      def describe(s)
        return "absent" unless s["present"]
        return "off" unless s["enabled"]

        case s["state"]
        when "connected" then s["connected"] ? "connected" : "hotspot"
        when "connecting" then "connecting"
        when "unavailable" then s["kind"] == "ethernet" && !s["carrier"] ? "no cable" : "unavailable"
        else s["state"] # disconnected, unmanaged, deactivating
        end
      end

      # Switching this one off must not lock the user out: only when the other interface is
      # connected and has an address. Switching on is always fine.
      def may_disable?(status, iface)
        other = status.values.find { |s| s["iface"] != iface }
        !!(other && other["connected"] && other["ip4"])
      end

      def set(iface, enabled, status: nil)
        kind = IFACES[iface] or raise Ampberry::Error, "unknown interface '#{iface}'"
        status ||= self.status
        if !enabled && !may_disable?(status, iface)
          raise Ampberry::Error, "#{LABELS[kind]} is the only way in — connect the other interface first"
        end

        if kind == "wifi"
          Run.run("nmcli", "radio", "wifi", enabled ? "on" : "off", timeout: 30)
        elsif enabled
          Run.run("nmcli", "device", "set", iface, "autoconnect", "yes", timeout: 30)
          Run.try_run("nmcli", "--wait", "20", "device", "connect", iface, timeout: 45) # fails harmlessly without a cable
        else
          Run.run("nmcli", "device", "set", iface, "autoconnect", "no", timeout: 30)
          Run.try_run("nmcli", "device", "disconnect", iface, timeout: 30)
        end
        self.status
      end

      private

      # [autoconnect?, "a.b.c.d/nn" or nil] from one nmcli call
      def details(iface)
        r = Run.try_run("nmcli", "-t", "-f", "GENERAL.AUTOCONNECT,IP4.ADDRESS", "device", "show", iface, quiet: true, read_only: true)
        return [true, nil] unless r.status.zero?

        [!r.out.match?(/^GENERAL\.AUTOCONNECT:no/), r.out[%r{^IP4\.ADDRESS\[1\]:(\d+\.\d+\.\d+\.\d+/\d+)}, 1]]
      end

      def active_ssid(text: nil)
        text ||= Run.try_run("nmcli", "-t", "-f", "ACTIVE,SSID", "device", "wifi", "list", "--rescan", "no", quiet: true, read_only: true).out
        text.each_line do |line|
          active, ssid = Wifi.split_terse(line)
          return ssid if active == "yes" && ssid && !ssid.empty?
        end
        nil
      end

      def carrier?(iface)
        File.read(File.join(Ampberry.root, "/sys/class/net/#{iface}/carrier")).include?("1")
      rescue SystemCallError
        false
      end
    end
  end
end
