# frozen_string_literal: true

require_relative "test_helper"

class UpdatesTest < AmpberryTest
  U = Ampberry::Updates

  def setup
    U.http = nil
    mkdirs("run/system-manager/sw/bin", "nix/store/abc-shairport-sync-5.5.2/bin", "run/ampberry")
    File.write(File.join(ROOT, "nix/store/abc-shairport-sync-5.5.2/bin/shairport-sync"), "")
    link = File.join(ROOT, "run/system-manager/sw/bin/shairport-sync")
    File.unlink(link) if File.symlink?(link)
    File.symlink(File.join(ROOT, "nix/store/abc-shairport-sync-5.5.2/bin/shairport-sync"), link)
    File.unlink(Ampberry.path(:updates)) if File.exist?(Ampberry.path(:updates))
  end

  def test_running_version_comes_from_the_store_path
    assert_equal "5.5.2", U.running_version
  end

  def test_check_up_to_date_and_cached
    U.http = ->(uri) { assert_match(/releases\/latest/, uri.to_s); [200, '{"tag_name":"5.5.2"}'] }
    r = U.check(now: Time.utc(2026, 10, 9, 1, 0, 0))
    assert_equal({ "running" => "5.5.2", "latest" => "5.5.2", "up_to_date" => true }, r.slice("running", "latest", "up_to_date"))
    assert_equal "2026-10-09T01:00:00Z", r["checked_at"]
    assert_equal true, U.status["up_to_date"], "cached"
  end

  def test_check_behind_and_errors_are_recorded
    U.http = ->(_u) { [200, '{"tag_name":"v5.6.0"}'] }
    r = U.check
    assert_equal "5.6.0", r["latest"]
    assert_equal false, r["up_to_date"]

    U.http = ->(_u) { [403, "rate limited"] }
    r = U.check
    assert_match(/HTTP 403/, r["error"])
    assert_equal "5.5.2", r["running"]
    assert_match(/HTTP 403/, U.status["error"], "the failed check is cached too")
  end

  def test_status_without_cache
    assert_equal({ "running" => "5.5.2", "releases_url" => U::RELEASES_URL }, U.status)
  end
end
