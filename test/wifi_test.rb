# frozen_string_literal: true

require_relative "test_helper"

class WifiTest < AirPlayOSTest
  W = AirPlayOS::Wifi

  def setup
    install_defaults
    mkdirs("boot/firmware")
    AirPlayOS::Config.save_json_atomic(AirPlayOS.path(:secrets), { "setup_psk" => "airplay-os-setup" })
    [AirPlayOS.path(:network_config), "#{AirPlayOS.path(:network_config)}.bak", AirPlayOS.path(:wifi_state)].each { |f| File.unlink(f) if File.exist?(f) }
  end

  def test_split_terse_unescapes
    assert_equal ["Pass the Juice", "63", "WPA2", "04:B4:FE:8B:68:B2", "6", "2437 MHz", "*"],
                 W.split_terse('Pass the Juice:63:WPA2:04\:B4\:FE\:8B\:68\:B2:6:2437 MHz:*')
    assert_equal ["a", "", "c"], W.split_terse("a::c")
    assert_equal %w[x y], W.split_terse("x:y\n")
  end

  def test_scan_dedupes_and_sorts
    list = fixture("nmcli-wifi-list.txt") +
           "Neighbour:40:WPA2:aa\\:bb\\:cc\\:dd\\:ee\\:ff:1:2412 MHz:\n" \
           "Neighbour:55:WPA2:aa\\:bb\\:cc\\:dd\\:ee\\:00:11:2462 MHz:\n" \
           "Cafe:30::11\\:22\\:33\\:44\\:55\\:66:6:2437 MHz:\n" \
           ":20:WPA2:00\\:00\\:00\\:00\\:00\\:01:6:2437 MHz:\n"
    nets = W.scan(text: list)
    assert_equal 3, nets.size, "one entry per SSID, hidden SSID dropped"
    assert_equal "Pass the Juice", nets[0]["ssid"]
    assert nets[0]["in_use"]
    assert_equal "04:B4:FE:8B:68:B2", nets[0]["bssid"]
    assert_equal ["Neighbour", 55], [nets[1]["ssid"], nets[1]["signal"]], "strongest BSSID kept per SSID"
    assert nets[2]["open"]
  end

  def test_status_from_fixtures
    st = W.status(device_text: fixture("nmcli-device-status.txt"), route_text: fixture("ip4-route-default.txt"),
                  profiles_text: fixture("nmcli-con-show.txt"), ip4: "192.168.178.221/24", eth_carrier: false)
    assert_equal "connected", st["wifi_state"]
    assert_equal "netplan-wlan0-Pass the Juice", st["connection"]
    assert st["wifi_connected"]
    refute st["hotspot"]
    assert st["online"]
    assert_equal "192.168.178.1", st["gateway"]
    assert_equal "unavailable", st["eth_state"]

    hot = W.status(device_text: "wlan0:wifi:connected:AirPlay-OS-setup\neth0:ethernet:unavailable:\n", route_text: "",
                   profiles_text: "AirPlay-OS-setup:uuid-1:802-11-wireless:wlan0:yes:no\nnetplan-eth0:uuid-2:802-3-ethernet::no:yes\n",
                   ip4: "10.42.0.1/24", eth_carrier: false)
    assert hot["hotspot"]
    refute hot["wifi_connected"]
    refute hot["online"]
    assert W.hotspot_active?(text: "AirPlay-OS-setup:u:802-11-wireless:wlan0:yes:no\n")
    refute W.hotspot_active?(text: "AirPlay-OS-setup:u:802-11-wireless::no:no\n")
  end

  def test_network_config_rendering_and_writeback
    yaml = W.render_network_config("Pass the Juice", 'secret"pass\\x', country: "DE")
    assert_match(/\Anetwork:\n  version: 2\n/, yaml)
    assert_match(/^  ethernets:\n    eth0:\n      dhcp4: true\n      dhcp6: true\n      optional: true\n/m, yaml, "eth0 rescue path kept")
    assert_includes yaml, 'regulatory-domain: "DE"'
    assert_match(/^        "Pass the Juice":\n          password: "secret\\"pass\\\\x"\n/m, yaml)
    assert_match(/^      optional: true\n\z/m, yaml, "wlan0 optional")
    assert_match(/^        "Open":\n          \{\}\n/m, W.render_network_config("Open", nil))

    assert W.write_network_config("Pass the Juice", "secretpass1")
    refute W.write_network_config("Pass the Juice", "secretpass1"), "unchanged content is not rewritten"
    assert W.write_network_config("Other", "secretpass2")
    assert File.exist?("#{AirPlayOS.path(:network_config)}.bak")
    assert_includes slurp(AirPlayOS.path(:network_config)), '"Other"'
    assert_includes slurp("#{AirPlayOS.path(:network_config)}.bak"), '"Pass the Juice"'
  end

  def test_connect_sequence_rollback_and_writeback
    profiles = +"netplan-wlan0-Pass the Juice:u1:802-11-wireless:wlan0:yes:yes\nAirPlay-OS-setup:u2:802-11-wireless:wlan0:yes:no\n"
    fail_join = false
    handler = lambda do |cmd, _opts|
      s = cmd.join(" ")
      case s
      when /\Anmcli -t -f NAME,UUID/ then { status: 0, out: profiles.dup }
      when /\Aip -4 route show proto kernel/ then { status: 0, out: "192.168.178.0/24 dev wlan0 scope link\n" }
      when /\Aip -4 route show default/ then { status: 0, out: "default via 192.168.178.1 dev wlan0\n" }
      when /\Anmcli -t -f DEVICE/ then { status: 0, out: "wlan0:wifi:connected:Home\neth0:ethernet:unavailable:\n" }
      when /\Aip -4 -o addr/ then { status: 0, out: "2: wlan0    inet 192.168.178.50/24 brd ...\n" }
      when /\Anmcli con down id AirPlay-OS-setup/
        profiles.sub!("AirPlay-OS-setup:u2:802-11-wireless:wlan0:yes", "AirPlay-OS-setup:u2:802-11-wireless::no")
        { status: 0 }
      when /\Anmcli --wait 45 con up id Home/
        fail_join ? { status: 4, err: "Error: Connection activation failed: (7) Secrets were required" } : { status: 0 }
      else { status: 0, out: "" }
      end
    end

    with_runner(handler) do
      st = W.connect("Home", "homepass123")
      add = cmds.find { |c| c.start_with?("nmcli con add type wifi") }
      assert_match(/con-name Home ssid Home connection\.autoconnect yes wifi-sec\.key-mgmt wpa-psk wifi-sec\.psk homepass123/, add)
      assert cmds.any? { |c| c.start_with?("nmcli con down id AirPlay-OS-setup") }, "hotspot taken down for the attempt"
      assert cmds.any? { |c| c.start_with?("nmcli --wait 45 con up id Home") }
      refute cmds.any? { |c| c.start_with?("nmcli con delete") }
      assert_match(/"Home":\n          password: "homepass123"/, slurp(AirPlayOS.path(:network_config)))
      assert_equal "Home", st["connection"]
    end

    fail_join = true
    profiles.replace("netplan-wlan0-Pass the Juice:u1:802-11-wireless:wlan0:yes:yes\nAirPlay-OS-setup:u2:802-11-wireless:wlan0:yes:no\n")
    with_runner(handler) do
      e = assert_raises(AirPlayOS::Error) { W.connect("Home", "wrongpass123") }
      assert_match(/could not join 'Home'.*Secrets were required/m, e.message)
      assert cmds.any? { |c| c.start_with?("nmcli con delete id Home") }, "new profile removed on failure"
      assert cmds.any? { |c| c.start_with?("nmcli --wait 30 con up id AirPlay-OS-setup") }, "hotspot restored on failure"
    end
    assert_raises(AirPlayOS::Error) { W.connect("Home", "short") }
    assert_raises(AirPlayOS::Error, "64 non-hex chars rejected") { W.connect("Home", "g" * 64) }
    assert_raises(AirPlayOS::Error) { W.connect("", "homepass123") }
  end

  def test_ensure_state_machine
    disconnected = lambda do |cmd, _opts|
      s = cmd.join(" ")
      case s
      when /\Anmcli -t -f DEVICE/ then { status: 0, out: "wlan0:wifi:disconnected:\neth0:ethernet:unavailable:\n" }
      when /\Anmcli -t -f NAME,UUID/ then { status: 0, out: "netplan-wlan0-Pass the Juice:u1:802-11-wireless::no:yes\n" }
      when /\Aip -4 route show/ then { status: 0, out: "" }
      when /\Aip -4 -o addr/ then { status: 1, out: "" }
      else { status: 0, out: "" }
      end
    end
    with_runner(disconnected) do
      r = W.ensure(now: 1000)
      assert_equal "waiting", r["action"]
      assert_equal 1, r["misses"]
      refute cmds.any? { |c| c.include?("con up id AirPlay-OS-setup") }
    end
    with_runner(disconnected) do
      r = W.ensure(now: 1200)
      assert_equal "hotspot-on", r["action"]
      assert cmds.any? { |c| c.start_with?("nmcli con add type wifi ifname wlan0 con-name AirPlay-OS-setup") }, "hotspot profile created"
      assert cmds.any? { |c| c.include?("802-11-wireless.mode ap") && c.include?("ipv4.method shared") && c.include?("wifi-sec.psk airplay-os-setup") }
      assert cmds.any? { |c| c.start_with?("nmcli --wait 30 con up id AirPlay-OS-setup") }
    end
    with_runner(->(cmd, opts) { device_mock(cmd, opts) }) do
      r = W.ensure(now: 1300)
      assert_equal "connected", r["action"]
      assert_equal 0, AirPlayOS::Config.load_json(AirPlayOS.path(:wifi_state))["misses"]
    end
  end
end
