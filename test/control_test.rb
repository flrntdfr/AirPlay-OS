# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "socket"
require "etc"

class ControlTest < AmpberryTest
  A = Ampberry::Actions
  C = Ampberry::Control

  def setup
    install_defaults
    File.unlink(Ampberry.path(:settings)) if File.exist?(Ampberry.path(:settings))
    actions_cfg([])
  end

  def actions_cfg(list) = Ampberry::Config.save_json_atomic(Ampberry.path(:actions), { "actions" => list })

  def test_custom_config_validation
    actions_cfg([{ "id" => "restart-avahi", "label" => "Restart mDNS", "exec" => ["/usr/bin/systemctl", "restart", "avahi-daemon"], "timeout" => 60 }])
    custom = A.load_custom
    assert_equal ["restart-avahi"], custom.keys
    assert_equal 60, custom["restart-avahi"]["timeout"]

    [[{ "id" => "Bad Id", "exec" => ["/bin/true"] }, /invalid action id/],
     [{ "id" => "x", "exec" => "systemctl restart foo" }, /exec must be/],
     [{ "id" => "x", "exec" => %w[systemctl restart] }, /absolute path/],
     [{ "id" => "x", "exec" => ["/bin/true"], "timeout" => 0 }, /timeout/],
     [{ "id" => "wifi-scan", "exec" => ["/bin/true"] }, /collides with a built-in/]].each do |bad, re|
      actions_cfg([bad])
      e = assert_raises(Ampberry::Error) { A.load_custom }
      assert_match re, e.message
    end
    actions_cfg([{ "id" => "dup", "exec" => ["/bin/true"] }, { "id" => "dup", "exec" => ["/bin/false"] }])
    assert_raises(Ampberry::Error) { A.load_custom }
  end

  def test_catalogue
    actions_cfg([{ "id" => "reboot", "label" => "Reboot", "exec" => ["/usr/bin/systemctl", "reboot"], "confirm" => true, "danger" => true }])
    by_id = A.list.to_h { |a| [a["id"], a] }
    assert by_id["wifi-scan"] && !by_id["wifi-scan"]["custom"]
    assert by_id["reboot"]["custom"] && by_id["reboot"]["confirm"] && by_id["reboot"]["danger"]
    refute by_id["reboot"].key?("exec"), "exec details are not exposed"
    assert_equal A.builtin_ids, by_id.values.reject { |a| a["custom"] }.map { |a| a["id"] }.sort
    assert_equal({ "ssid" => "string", "psk" => "string" }, by_id["wifi-connect"]["params"])
  end

  def test_run_action_validation
    actions_cfg([{ "id" => "reboot", "exec" => ["/usr/bin/systemctl", "reboot"] }])
    assert_match(/unknown action/, A.run_action("nope")["error"])
    assert_match(/invalid action id/, A.run_action("Bad!")["error"])
    assert_match(/unexpected parameter/, A.run_action("wifi-scan", { "extra" => 1 })["error"])
    assert_match(/must be a string/, A.run_action("wifi-connect", { "ssid" => ["x"] })["error"])
    assert_match(/invalid settings.*volume_max_db/, A.run_action("settings-apply", { "settings" => { "volume_max_db" => 9 } })["error"])
    assert_match(/take no parameters/, A.run_action("reboot", { "x" => 1 })["error"])
  end

  def test_run_action_execution
    actions_cfg([{ "id" => "restart-avahi", "exec" => ["/usr/bin/systemctl", "restart", "avahi-daemon"] }, { "id" => "ok", "exec" => ["/bin/true"] }])
    handler = lambda do |cmd, opts|
      next { status: 3, err: "Failed to restart avahi-daemon.service: Unit not found.\n" } if cmd.join(" ") == "/usr/bin/systemctl restart avahi-daemon"
      next { status: 0, out: "done\n" } if cmd == ["/bin/true"]

      device_mock(cmd, opts) || { status: 0, out: "" }
    end
    with_runner(handler) do
      r = A.run_action("wifi-status")
      assert r["ok"]
      assert_equal "netplan-wlan0-Pass the Juice", r["result"]["status"]["connection"]

      r = A.run_action("restart-airplay")
      assert r["ok"]
      assert_includes cmds, "systemctl restart nqptp shairport-sync avahi-daemon"

      r = A.run_action("settings-apply", { "settings" => { "name" => "Kitchen" } })
      assert r["ok"], r["error"]
      assert_equal "Kitchen", r["result"]["settings"]["name"]
      assert_equal "Kitchen", Ampberry::Config.load_json(Ampberry.path(:settings))["name"]
      assert_includes slurp(Ampberry.path(:shairport_conf)), 'name = "Kitchen";'

      r = A.run_action("restart-avahi")
      refute r["ok"]
      assert_match(/exit status 3/, r["error"])
      assert_match(/Unit not found/, r["output"])
      r = A.run_action("ok")
      assert r["ok"] && r["result"]["output"].include?("done")
    end
    with_runner(->(_c, _o) { { status: 0 } }) do
      r = A.run_action("clean-reboot", { "reset_settings" => true })
      assert r["ok"] && r["result"]["rebooting"]
      assert_kind_of Proc, r[:after], "reboot deferred until after the response"
      refute File.exist?(Ampberry.path(:settings))
      assert_includes cmds, "cloud-init clean --logs"
      refute_includes cmds, "systemctl reboot"
      r[:after].call
      assert_includes cmds, "systemctl reboot"
    end
  end

  def roundtrip(request, **opts)
    out = StringIO.new
    rc = C.handle_stream(StringIO.new(request), out, peer_uid: Process.uid, allowed_users: [Etc.getpwuid(Process.uid).name], **opts)
    [JSON.parse(out.string), rc]
  end

  def test_handle_stream
    with_runner(->(cmd, opts) { device_mock(cmd, opts) }) do
      res, rc = roundtrip(%({"action":"wifi-status"}\n))
      assert res["ok"], res.inspect
      assert_equal 0, rc
    end
    assert_match(/unknown action/, roundtrip(%({"action":"nope"}\n)).first["error"])
    assert_match(/invalid JSON/, roundtrip("not json\n").first["error"])
    assert_match(/must be an object/, roundtrip("[1,2]\n").first["error"])
    assert_match(/empty request/, roundtrip("").first["error"])
    assert_match(/not allowed/, roundtrip(%({"action":"wifi-status"}\n), allowed_users: ["nobody-else"]).first["error"])
  end

  # STDOUT of the handler is the client socket: log lines must never land there (they broke the
  # UI's JSON parsing on the device).
  def test_log_lines_go_to_stderr_not_the_socket
    Ampberry::Log.init("control")
    out, err = capture_io { roundtrip(%({"action":"wifi-status"}\n), allowed_users: ["nobody-else"]) }
    assert_empty out
    assert_match(/rejected connection/, err)
  end

  def test_over_a_real_unix_socket
    path = File.join(ROOT, "ctl.sock")
    File.unlink(path) if File.exist?(path)
    server = UNIXServer.new(path)
    me = Etc.getpwuid(Process.uid).name
    thread = Thread.new do
      conn = server.accept
      Ampberry::Run.runner = ->(cmd, opts) { device_mock(cmd, opts) || { status: 0, out: "" } }
      C.handle_stream(conn, conn, allowed_users: [me])
      conn.close
    end
    res = C::Client.new(socket_path: path, timeout: 5).call("wifi-status")
    thread.join
    assert res["ok"], res.inspect
    assert_equal "netplan-wlan0-Pass the Juice", res["result"]["status"]["connection"]

    # oversized request is refused
    thread = Thread.new { conn = server.accept; C.handle_stream(conn, conn, allowed_users: [me]); conn.close }
    UNIXSocket.open(path) do |s|
      s.write(("x" * 70_000) + "\n")
      assert_match(/too large/, JSON.parse(s.gets)["error"])
    end
    thread.join

    missing = C::Client.new(socket_path: File.join(ROOT, "missing.sock"), timeout: 1).call("wifi-status")
    refute missing["ok"]
    assert_match(/unavailable/, missing["error"])
  ensure
    Ampberry::Run.runner = nil
    server&.close
  end
end
