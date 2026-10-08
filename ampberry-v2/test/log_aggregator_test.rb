# frozen_string_literal: true

require_relative "test_helper"

class LogAggregatorTest < AmpberryTest
  L = Ampberry::LogAggregator

  def entry(unit, msg, ts: 1_759_950_000_000_000, **extra)
    JSON.generate({ "_SYSTEMD_UNIT" => unit, "MESSAGE" => msg, "__REALTIME_TIMESTAMP" => ts.to_s }.merge(extra))
  end

  def setup
    @path = File.join(ROOT, "var/log/ampberry.log")
    File.unlink(@path) if File.exist?(@path)
    @agg = L.new(path: @path)
  end

  def test_journalctl_command_follows_the_whole_journal_as_json
    cmd = @agg.journalctl_cmd
    assert_equal "journalctl", cmd.first
    assert_includes cmd, "-f"
    assert_equal "json", cmd[cmd.index("-o") + 1]
    # journalctl rejects "-u … + _TRANSPORT=kernel" ('"+" can only be used between terms'):
    # selection happens in process_line, not on the command line
    refute_includes cmd, "-u"
    refute_includes cmd, "+"
  end

  def test_selection_covers_units_instances_and_kernel_only
    assert_match(/ control  action/, @agg.process_line(entry("ampberry-control@7-123-0.service", "action settings-show (uid 996)")))
    assert_match(/ control  action settings-show \(uid 996\)\z/,
                 @agg.process_line(entry("ampberry-control@7-123-0.service", "2026-10-09T00:49:22+0200 [INFO] control: action settings-show (uid 996)")),
                 "our own timestamp/level prefix is dropped")
    assert_nil @agg.process_line(entry("ampberry-wifi-fallback.service", '  "wifi_state": "connected",')), "JSON fragments dropped"
    assert_nil @agg.process_line(entry("cron.service", "(root) CMD (something)")), "unlisted unit dropped"
    assert_nil @agg.process_line(entry("init.scope", "Started shairport-sync.service - Shairport Sync.")), "systemd job chatter dropped"
  end

  def test_formatting_and_tags
    line = @agg.process_line(entry("shairport-sync.service", "  Connection from 192.168.178.40  (\"Flo's iPhone\")  "))
    assert_match(/\A\d\d:\d\d:\d\d airplay  Connection from 192\.168\.178\.40 \("Flo's iPhone"\)\z/, line)
    assert_match(/ control  action settings-apply/, @agg.process_line(entry("ampberry-control@3-1234-5678.service", "action settings-apply (uid 998)")))
    assert_match(/ track    ▶ Blue in Green/, @agg.process_line(entry("ampberry-metadata.service", "▶ Blue in Green — Miles Davis")))
    assert_match(/ provision/, @agg.process_line(entry("cloud-final.service", "[settings] done (3s)")))
  end

  def test_relevance_filters
    assert_nil @agg.process_line(entry("", "usb 1-1.2: new high-speed USB device", "_TRANSPORT" => "kernel")), "unrelated kernel noise dropped"
    assert_match(/ kernel   Under-voltage detected!/, @agg.process_line(entry("", "Under-voltage detected!", "_TRANSPORT" => "kernel")))
    assert_nil @agg.process_line(entry("NetworkManager.service", "<info>  [1759950000.1] audit: op=\"checkpoint-create\"")), "NM chatter dropped"
    assert_match(/ network  .*wlan0/, @agg.process_line(entry("NetworkManager.service", "<info> device (wlan0): state change: config -> ip-config")))
    assert_nil @agg.process_line(entry("ampberry-ui.service", "Started GET \"/api/log?from=120\" for 192.168.178.40")), "UI access log dropped"
    assert_match(/ ui       .*Listening/, @agg.process_line(entry("ampberry-ui.service", "* Listening on http://[::]:80")))
    assert_match(/ ssh      Accepted publickey/, @agg.process_line(entry("ssh.service", "Accepted publickey for pi from 192.168.178.30 port 51234 ssh2")))
    assert_nil @agg.process_line(entry("some-other.service", "hello")), "unknown units dropped"
    assert_nil @agg.process_line("not json")
    assert_nil @agg.process_line(entry("shairport-sync.service", "   "))
  end

  def test_write_and_rotate
    @agg.max_size = 2000
    @agg.keep = 600
    40.times { |i| @agg.write_line(@agg.format_line(Time.now, "airplay", "line #{i} #{'x' * 40}")) }
    size = File.size(@path)
    assert_operator size, :<=, 2000 + 200, "rotated to roughly the kept tail"
    content = File.read(@path)
    assert_match(/\A\d\d:\d\d:\d\d log      == log rotated\n/, content)
    assert_includes content, "line 39"
    refute_includes content, "line 0 ", "oldest lines dropped"
    assert_equal "644", format("%o", File.stat(@path).mode & 0o777)
  end
end
