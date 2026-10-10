# frozen_string_literal: true

require_relative "test_helper"

# The Network card: status of wlan0/eth0 from nmcli, the lock-out rule, and the switches.
class NetworkTest < AirPlayOSTest
  N = AirPlayOS::Network

  DEVICES = "wlan0:wifi:connected:netplan-wlan0-Pass the Juice\nlo:loopback:connected (externally):lo\np2p-dev-wlan0:wifi-p2p:disconnected:\neth0:ethernet:unavailable:\n"
  WIFI_LIST = "no:Neighbour\nyes:Pass the Juice\n"

  # nmcli as a connected-over-Wi-Fi box with the cable unplugged
  def nmcli(cmd, eth_ip: nil, radio: "enabled", eth_auto: "yes")
    s = cmd.join(" ")
    case s
    when /device status\z/ then { status: 0, out: DEVICES }
    when /radio wifi\z/ then { status: 0, out: "#{radio}\n" }
    when /device show wlan0\z/ then { status: 0, out: "GENERAL.AUTOCONNECT:yes\nIP4.ADDRESS[1]:192.168.178.221/24\n" }
    when /device show eth0\z/ then { status: 0, out: "GENERAL.AUTOCONNECT:#{eth_auto}\n#{eth_ip ? "IP4.ADDRESS[1]:#{eth_ip}\n" : ''}" }
    when /device wifi list/ then { status: 0, out: WIFI_LIST }
    else { status: 0, out: "" }
    end
  end

  def test_status_reads_both_interfaces
    with_runner(->(cmd, _o) { nmcli(cmd) }) do
      st = N.status
      w = st["wlan0"]
      assert_equal %w[wifi Wi‑Fi connected], [w["kind"], w["label"], w["state"]]
      assert w["connected"]
      assert w["enabled"]
      assert_equal "192.168.178.221/24", w["ip4"]
      assert_equal "Pass the Juice", w["ssid"]
      assert_equal "connected", N.describe(w)
      e = st["eth0"]
      assert e["present"]
      refute e["connected"]
      assert e["enabled"], "autoconnect yes = switched on"
      assert_nil e["ip4"]
      assert_equal "no cable", N.describe(e)
    end
  end

  def test_describe_off_absent_and_hotspot
    with_runner(->(cmd, _o) { nmcli(cmd, radio: "disabled", eth_auto: "no") }) do
      st = N.status
      assert_equal "off", N.describe(st["wlan0"])
      assert_equal "off", N.describe(st["eth0"])
    end
    with_runner(->(cmd, _o) { nmcli(cmd) }) do
      hotspot = N.status(device_text: "wlan0:wifi:connected:AirPlay-OS-setup\n", radio_text: "enabled\n", wifi_text: "")
      refute hotspot["wlan0"]["connected"], "the onboarding hotspot is not a connection to the LAN"
      assert_equal "absent", N.describe(hotspot["eth0"])
    end
  end

  def test_lock_out_rule
    with_runner(->(cmd, _o) { nmcli(cmd) }) do
      st = N.status
      refute N.may_disable?(st, "wlan0"), "Wi‑Fi is the only connection"
      assert N.may_disable?(st, "eth0"), "the (unconnected) cable may be switched off"
    end
    with_runner(->(cmd, _o) { nmcli(cmd, eth_ip: "192.168.178.50/24").merge(cmd.join(" ").end_with?("device status") ? { out: DEVICES.sub("eth0:ethernet:unavailable:", "eth0:ethernet:connected:Wired connection 1") } : {}) }) do
      st = N.status
      assert N.may_disable?(st, "wlan0"), "Ethernet is connected: Wi‑Fi may go"
      assert N.may_disable?(st, "eth0")
    end
  end

  def test_set_refuses_to_cut_the_only_way_in_and_switches_otherwise
    with_runner(->(cmd, _o) { nmcli(cmd) }) do
      e = assert_raises(AirPlayOS::Error) { N.set("wlan0", false) }
      assert_match(/only way in/, e.message)
      refute cmds.any? { |c| c.include?("radio wifi off") }

      N.set("eth0", false)
      assert_includes cmds, "nmcli device set eth0 autoconnect no"
      assert_includes cmds, "nmcli device disconnect eth0"
      N.set("eth0", true)
      assert_includes cmds, "nmcli device set eth0 autoconnect yes"
      assert cmds.any? { |c| c.end_with?("device connect eth0") }
      N.set("wlan0", true)
      assert_includes cmds, "nmcli radio wifi on"
      assert_raises(AirPlayOS::Error) { N.set("usb0", true) }
    end
  end

  def test_actions_are_exposed
    ids = AirPlayOS::Actions.list(path: "/nonexistent").map { |a| a["id"] }
    assert_includes ids, "network-status"
    assert_includes ids, "network-set"
    with_runner(->(cmd, _o) { nmcli(cmd) }) do
      r = AirPlayOS::Actions.run_action("network-set", { "iface" => "wlan0", "enabled" => false })
      refute r["ok"]
      assert_match(/only way in/, r["error"])
      r = AirPlayOS::Actions.run_action("network-status")
      assert r["ok"]
      assert_equal "connected", r["result"]["network"]["wlan0"]["state"]
    end
  end
end
