# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "time"
require "fileutils"

module Ampberry
  # Is the running shairport-sync the latest release? The version comes from the Nix store path
  # behind /run/system-manager/sw/bin/shairport-sync (the binary's own -V string lags upstream);
  # the latest from GitHub's releases API. The result is cached in /run/ampberry/updates.json
  # (written by ampberry-updates.timer daily, or on demand from the UI); no privilege needed.
  module Updates
    REPO = "mikebrady/shairport-sync"
    LATEST_URL = "https://api.github.com/repos/#{REPO}/releases/latest"
    RELEASES_URL = "https://github.com/#{REPO}/releases"
    TIMEOUT = 8

    DEFAULT_HTTP = lambda do |uri|
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |h|
        res = h.get(uri.request_uri, { "Accept" => "application/vnd.github+json", "User-Agent" => "ampberry/#{Ampberry::VERSION}" })
        [res.code.to_i, res.body]
      end
    end

    class << self
      attr_accessor :http # injectable for tests: ->(uri) { [status, body] }

      def running_version(bin: "/run/system-manager/sw/bin/shairport-sync")
        File.realpath(File.join(Ampberry.root, bin))[/shairport-sync-(\d[\w.]*?)(?:\/|$)/, 1]
      rescue SystemCallError
        nil
      end

      # { "version" => "5.5.2", "tag" => "5.5.2" } — the tag is what the update job fetches.
      def latest_release
        status, body = (http || DEFAULT_HTTP).call(URI(LATEST_URL))
        raise Ampberry::Error, "GitHub answered HTTP #{status}" unless status == 200

        tag = JSON.parse(body)["tag_name"].to_s
        raise Ampberry::Error, "no release tag in GitHub's answer" if tag.empty?

        { "version" => tag.delete_prefix("v"), "tag" => tag }
      end

      def latest_version = latest_release["version"]

      # Fetch, compare, cache. Never raises: a failed check is recorded as such.
      def check(now: Time.now)
        result = { "running" => running_version, "checked_at" => now.utc.iso8601, "releases_url" => RELEASES_URL }
        begin
          release = latest_release
          latest = release["version"]
          result["latest"] = latest
          result["latest_tag"] = release["tag"]
          result["up_to_date"] = result["running"] ? Gem::Version.new(result["running"]) >= Gem::Version.new(latest) : nil
        rescue StandardError => e
          result["error"] = e.message
        end
        write_cache(result)
        result
      end

      # The cached result (with the running version refreshed), or just the running version.
      def status
        cached = JSON.parse(File.read(Ampberry.path(:updates)))
        cached.merge("running" => running_version || cached["running"])
      rescue SystemCallError, JSON::ParserError
        { "running" => running_version, "releases_url" => RELEASES_URL }
      end

      private

      def write_cache(result)
        path = Ampberry.path(:updates)
        FileUtils.mkdir_p(File.dirname(path))
        tmp = "#{path}.#{Process.pid}.tmp"
        File.write(tmp, JSON.pretty_generate(result))
        File.rename(tmp, path)
      rescue SystemCallError => e
        Log.warning("updates: cannot write #{path}: #{e.message}") if Log.name
      end
    end
  end
end
