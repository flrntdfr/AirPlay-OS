# frozen_string_literal: true

require "json"
require "fileutils"

module Ampberry
  # The appliance's one live log: /var/log/ampberry.log, streamed as the backdrop of every UI page.
  # Follows the journal for the units that matter to a speaker and writes compact lines:
  #   20:41:07 airplay  Connection from 192.168.178.40 ("Flo's iPhone")
  #   20:41:09 track    ▶ Blue in Green — Miles Davis
  #   20:55:12 control  action settings-apply (uid 998)
  #   21:03:40 kernel   Under-voltage detected!
  # Runs as root (journal access) in ampberry-log.service; the file is world-readable and size-capped
  # (rotation keeps the tail; readers that poll by offset notice the shrink and start over).
  class LogAggregator
    # Sources that make it into the log (unit name without .service / @instance → tag). journalctl
    # cannot OR unit filters with a kernel match ("+" only joins plain terms), so the whole journal
    # is followed and selected here — on this appliance that is a few lines a minute.
    TAGS = {
      "shairport-sync" => "airplay", "nqptp" => "ptp", "ampberry-metadata" => "track", "ampberry-ui" => "ui",
      "ampberry-control" => "control", "ampberry-redeploy" => "redeploy", "ampberry-wifi-fallback" => "wifi",
      "ampberry-firewall" => "firewall", "ampberry-log" => "log", "avahi-daemon" => "mdns", "NetworkManager" => "network",
      "ssh" => "ssh", "cloud-init" => "provision", "cloud-final" => "provision", "unattended-upgrades" => "updates",
      "kernel" => "kernel"
    }.freeze

    # Per-source relevance filters (nil = everything). The point is signal, not completeness.
    FILTERS = {
      "kernel" => /voltage|throttl|pcm512x|snd_|hifiberry|bcm2835|brcmfmac|wlan0|Out of memory|I\/O error|segfault/i,
      "network" => /wlan0|Ampberry-setup|hotspot|state change|connected|disconnect|dhcp4|address|carrier|policy/i,
      "mdns" => /Registering|established|Withdraw|New relevant interface|Interface .* no longer|Host name|Server startup/i,
      "ssh" => /Accepted|Failed|Invalid user|Disconnected from|Received disconnect|session (opened|closed)|Server listening/,
      "updates" => /Packages that|Installing|upgraded|Packages that were upgraded|security|No packages found|error/i,
      "ui" => /error|fail|Puma|Listening|Shutting|SIGTERM/i,
      "ptp" => /start|clock|master|lost|error|warn/i
    }.freeze

    # Our own tools log "2026-10-09T00:49:22+0200 [INFO] control: …" — the journal already carries
    # the time and the tag column names the source, so that prefix is dropped.
    OWN_PREFIX = /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d{4} \[(?:INFO|WARN|ERROR|DEBUG)\] [\w-]+: /
    # JSON fragments (the Wi-Fi tool prints its status as a document) are not log lines.
    JSON_FRAGMENT = /\A(?:[{}\[\]],?|"[^"]*":.*)\z/

    MAX_SIZE = 4 * 1024 * 1024
    KEEP = 1 * 1024 * 1024
    MAX_LINE = 600

    attr_reader :path
    attr_accessor :max_size, :keep

    def initialize(path: Ampberry.path(:applog))
      @path = path
      @max_size = MAX_SIZE
      @keep = KEEP
      @stop = false
    end

    def journalctl_cmd
      ["journalctl", "-f", "-n", "200", "-q", "--no-pager", "-o", "json"]
    end

    # Follow the journal forever; restart journalctl if it exits.
    def run
      %w[TERM INT].each { |s| trap(s) { @stop = true } }
      write_line(format_line(Time.now, "log", "== ampberry log #{Ampberry::VERSION} started (#{Time.now.strftime('%Y-%m-%d')})"))
      until @stop
        r, w = IO.pipe
        pid = Process.spawn(*journalctl_cmd, out: w, err: w, in: File::NULL)
        w.close
        r.each_line do |line|
          break if @stop
          formatted = process_line(line)
          write_line(formatted) if formatted
        end
        r.close
        Process.kill("TERM", pid) rescue nil
        Process.wait(pid) rescue nil
        sleep 2 unless @stop
      end
      true
    end

    # One journal JSON record → formatted line, or nil when irrelevant.
    def process_line(json_line)
      entry = JSON.parse(json_line)
      return nil unless entry.is_a?(Hash)

      msg = entry["MESSAGE"]
      return nil unless msg.is_a?(String) && !msg.strip.empty?

      tag = tag_for(entry)
      return nil unless tag
      return nil if (re = FILTERS[tag]) && !msg.match?(re)

      msg = msg.strip.sub(OWN_PREFIX, "").gsub(/\s+/, " ")
      return nil if msg.empty? || msg.match?(JSON_FRAGMENT)
      msg = "#{msg[0, MAX_LINE - 1]}…" if msg.length > MAX_LINE
      t = entry["__REALTIME_TIMESTAMP"] ? Time.at(entry["__REALTIME_TIMESTAMP"].to_i / 1_000_000.0) : Time.now
      format_line(t, tag, msg)
    rescue JSON::ParserError
      nil
    end

    def tag_for(entry)
      return "kernel" if entry["_TRANSPORT"] == "kernel"

      unit = entry["_SYSTEMD_UNIT"].to_s.sub(/\.service\z/, "").sub(/@.*\z/, "")
      TAGS[unit] || (entry["SYSLOG_IDENTIFIER"] && TAGS[entry["SYSLOG_IDENTIFIER"]])
    end

    def format_line(time, tag, msg)
      format("%s %-8s %s", time.strftime("%H:%M:%S"), tag, msg)
    end

    def write_line(line)
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, "a") do |f|
        f.puts(line)
      end
      File.chmod(0o644, @path)
      rotate if File.size(@path) > @max_size
    end

    # Keep the tail; readers polling by offset see size < offset and start over.
    def rotate
      tail = File.binread(@path, @keep, File.size(@path) - @keep)
      cut = tail.index("\n")
      tail = tail[(cut + 1)..] if cut
      File.binwrite("#{@path}.tmp", "#{format_line(Time.now, 'log', '== log rotated')}\n#{tail}")
      File.chmod(0o644, "#{@path}.tmp")
      File.rename("#{@path}.tmp", @path)
    end
  end
end
