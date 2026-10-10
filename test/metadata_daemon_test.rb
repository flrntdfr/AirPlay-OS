# frozen_string_literal: true

require_relative "test_helper"

class MetadataDaemonTest < AirPlayOSTest
  def test_publish_writes_snapshot_and_cover_atomically
    run_dir = File.join(ROOT, "run/airplay-os-test")
    d = AirPlayOS::MetadataDaemon.new(pipe: File.join(ROOT, "nonexistent-pipe"), run_dir: run_dir)
    assert d.publish(force: true)
    snap = JSON.parse(File.read(File.join(run_dir, "now-playing.json")))
    refute snap["playing"]
    assert_nil snap["cover_file"]

    item = AirPlayOS::Metadata.encode_item("ssnc", "PICT", "\xFF\xD8\xFF\xE0".b + ("x" * 50))
    d.parser.feed(item).each { |i| d.parser.apply(i) }
    d.parser.feed(AirPlayOS::Metadata.encode_item("core", "minm", "Song")).each { |i| d.parser.apply(i) }
    assert d.publish(force: true)
    snap = JSON.parse(File.read(File.join(run_dir, "now-playing.json")))
    assert_equal "Song", snap["title"]
    assert_match(/\Acover-[0-9a-f]{40}\.jpg\z/, snap["cover_file"])
    assert File.exist?(File.join(run_dir, snap["cover_file"]))
    assert_empty Dir.glob(File.join(run_dir, "*.tmp.*")), "no temp files left"

    refute d.publish(now: Time.now.to_f), "not due yet (idle, within heartbeat)"
    assert d.publish(now: Time.now.to_f + 10), "heartbeat"

    d.parser.feed(AirPlayOS::Metadata.encode_item("ssnc", "pend")).each { |i| d.parser.apply(i) }
    d.publish(force: true)
    snap = JSON.parse(File.read(File.join(run_dir, "now-playing.json")))
    assert_nil snap["cover_file"]
    assert_empty Dir.glob(File.join(run_dir, "cover-*")), "old cover removed"
  end

  def test_run_without_pipe_terminates_after_max_iterations
    d = AirPlayOS::MetadataDaemon.new(pipe: File.join(ROOT, "nonexistent-pipe"), run_dir: File.join(ROOT, "run/airplay-os-test2"))
    assert d.run(max_iterations: 1)
    assert File.exist?(File.join(ROOT, "run/airplay-os-test2/now-playing.json"))
  end
end
