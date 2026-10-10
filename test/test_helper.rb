# frozen_string_literal: true

require "minitest/autorun"

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8
require "tmpdir"
require "fileutils"
require "json"

ROOT = Dir.mktmpdir("airplay-os-test-")
ENV["AIRPLAY_OS_ROOT"] = ROOT
Minitest.after_run { FileUtils.remove_entry(ROOT) }

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "airplay_os"

module TestHelpers
  FIXTURES = File.expand_path("fixtures", __dir__)

  def fixture(name) = File.read(File.join(FIXTURES, name))

  def mkdirs(*rel) = rel.each { |r| FileUtils.mkdir_p(File.join(ROOT, r)) }

  def spit(path, text)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def slurp(path) = File.read(path)

  DEFAULTS = {
    "name" => "Ampberry", "password" => "", "interpolation" => "auto", "output_format" => "S32_LE",
    "volume_max_db" => -6.0, "volume_range_db" => 60
  }.freeze

  def install_defaults(extra = {})
    mkdirs("etc/airplay-os", "var/lib/airplay-os", "var/log/airplay-os", "run/shairport-sync", "etc")
    AirPlayOS::Config.save_json_atomic(AirPlayOS.path(:defaults), DEFAULTS.merge(extra))
  end

  # Run the block with every command intercepted. +handler+ is a lambda (cmd Array, opts Hash) →
  # {status:, out:, err:} or nil; without one, device_mock answers. Every call is recorded in
  # @cmds (joined argv strings).
  def with_runner(handler = nil)
    @cmds = []
    AirPlayOS::Run.runner = lambda do |cmd, opts|
      @cmds << cmd.join(" ")
      (handler ? handler.call(cmd, opts) : device_mock(cmd, opts)) || { status: 0, out: "", err: "" }
    end
    yield
  ensure
    AirPlayOS::Run.runner = nil
  end

  def cmds = @cmds

  # A plausible connected device for mocks.
  def device_mock(cmd, _opts)
    s = cmd.join(" ")
    case s
    when %r{\Aip -4 route show proto kernel} then { status: 0, out: "192.168.178.0/24 dev wlan0 scope link src 192.168.178.221\n" }
    when %r{\Aip -4 route show default} then { status: 0, out: "default via 192.168.178.1 dev wlan0\n" }
    when %r{\Anmcli -t -f DEVICE} then { status: 0, out: "wlan0:wifi:connected:netplan-wlan0-Pass the Juice\neth0:ethernet:unavailable:\n" }
    when %r{\Anmcli -t -f NAME} then { status: 0, out: "netplan-wlan0-Pass the Juice:u1:802-11-wireless:wlan0:yes:yes\n" }
    when %r{\Aip -4 -o addr} then { status: 0, out: "2: wlan0    inet 192.168.178.221/24 brd 192.168.178.255\n" }
    when %r{\Ahostnamectl hostname --pretty} then { status: 0, out: "Ampberry\n" }
    when %r{\Aloginctl show-user} then { status: 0, out: "no\n" }
    when /\Adpkg-query/ then { status: 1, out: "" }
    when %r{\Asystemctl is-active} then { status: 0, out: "active\n" }
    end
  end
end

class AirPlayOSTest < Minitest::Test
  include TestHelpers
end
