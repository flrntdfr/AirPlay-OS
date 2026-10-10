# frozen_string_literal: true

require "net/http"
require "uri"

module AirPlayOS
  # Remote control of the AirPlay *sender* (play/pause, next, previous). shairport-sync hands us
  # the session's DACP id and Active-Remote token in the metadata; the phone advertises its DACP
  # server as iTunes_Ctrl_<dacp_id>._dacp._tcp. One HTTP GET with the token is the command.
  # Needs no privilege: the web UI calls it directly (as the airplay-os user).
  module Remote
    COMMANDS = %w[playpause play pause nextitem previtem].freeze
    TIMEOUT = 3

    DEFAULT_HTTP = lambda do |uri, headers|
      Net::HTTP.start(uri.host, uri.port, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |h|
        res = h.get(uri.request_uri, headers)
        [res.code.to_i, res.body]
      end
    end

    class << self
      attr_accessor :http # injectable for tests: ->(uri, headers) { [status, body] }

      # [host, port] of the sender's DACP service, or nil.
      def discover(dacp_id)
        out = Run.capture("avahi-browse", "-rpt", "_dacp._tcp", timeout: 10)
        out.each_line do |line|
          f = line.chomp.split(";")
          next unless f[0] == "=" && f[2] == "IPv4" && f[3].to_s.casecmp?("iTunes_Ctrl_#{dacp_id}")

          return [f[7], f[8].to_i]
        end
        nil
      end

      # `now` is the now-playing snapshot (dacp_id, active_remote). Returns a small result hash.
      def command(cmd, now)
        raise AirPlayOS::Error, "unknown remote command #{cmd}" unless COMMANDS.include?(cmd)

        id = now["dacp_id"].to_s
        token = now["active_remote"].to_s
        raise AirPlayOS::Error, "no AirPlay session to control" if !now["active"] || id.empty? || token.empty?

        host, port = discover(id)
        raise AirPlayOS::Error, "the sender does not advertise remote control (DACP)" unless host

        status, = (http || DEFAULT_HTTP).call(URI("http://#{host}:#{port}/ctrl-int/1/#{cmd}"), { "Active-Remote" => token })
        raise AirPlayOS::Error, "sender answered HTTP #{status}" unless (200..299).cover?(status)

        { "command" => cmd, "sender" => "#{host}:#{port}" }
      end
    end
  end
end
