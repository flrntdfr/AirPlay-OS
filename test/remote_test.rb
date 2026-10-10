# frozen_string_literal: true

require_relative "test_helper"

class RemoteTest < AirPlayOSTest
  R = AirPlayOS::Remote

  BROWSE = <<~OUT
    +;wlan0;IPv6;iTunes_Ctrl_8F2C1A3B9D4E6F70;_dacp._tcp;local
    +;wlan0;IPv4;iTunes_Ctrl_8F2C1A3B9D4E6F70;_dacp._tcp;local
    =;wlan0;IPv6;iTunes_Ctrl_8F2C1A3B9D4E6F70;_dacp._tcp;local;Flos-iPhone.local;fe80::1c2b:3d4e:5f60:7a8b;49152;"txtvers=1" "Ver=131077"
    =;wlan0;IPv4;iTunes_Ctrl_8F2C1A3B9D4E6F70;_dacp._tcp;local;Flos-iPhone.local;192.168.178.40;49152;"txtvers=1" "Ver=131077"
    =;wlan0;IPv4;iTunes_Ctrl_0000000000000001;_dacp._tcp;local;other.local;192.168.178.41;3689;"txtvers=1"
  OUT

  def setup
    R.http = nil
  end

  def now(active: true) = { "active" => active, "dacp_id" => "8f2c1a3b9d4e6f70", "active_remote" => "1234567890" }

  def test_playpause_hits_the_senders_dacp_server
    calls = []
    R.http = ->(uri, headers) { calls << [uri.to_s, headers]; [204, ""] }
    with_runner(->(cmd, _o) { cmd.first == "avahi-browse" ? { status: 0, out: BROWSE } : { status: 1 } }) do
      res = R.command("playpause", now)
      assert_equal "192.168.178.40:49152", res["sender"]
    end
    assert_equal [["http://192.168.178.40:49152/ctrl-int/1/playpause", { "Active-Remote" => "1234567890" }]], calls
  end

  def test_errors_are_explicit
    R.http = ->(_u, _h) { [403, ""] }
    with_runner(->(_c, _o) { { status: 0, out: BROWSE } }) do
      assert_raises(AirPlayOS::Error) { R.command("playpause", now(active: false)) }
      assert_raises(AirPlayOS::Error) { R.command("playpause", now.merge("active_remote" => "")) }
      assert_raises(AirPlayOS::Error) { R.command("volumeup", now) }
      assert_raises(AirPlayOS::Error) { R.command("playpause", now.merge("dacp_id" => "deadbeef")) } # not advertised
      e = assert_raises(AirPlayOS::Error) { R.command("playpause", now) }
      assert_match(/HTTP 403/, e.message)
    end
  end

  def test_metadata_carries_the_remote_fields
    m = AirPlayOS::Metadata.new
    m.feed(AirPlayOS::Metadata.encode_item("ssnc", "daid", "8F2C1A3B9D4E6F70") + AirPlayOS::Metadata.encode_item("ssnc", "acre", "1234567890\n")).each { |i| m.apply(i) }
    assert_equal "8F2C1A3B9D4E6F70", m.snapshot["dacp_id"]
    assert_equal "1234567890", m.snapshot["active_remote"]
  end
end
