# frozen_string_literal: true

require_relative "test_helper"

# The minimal AirPlay status lines the metadata daemon writes to the live log.
class MetadataAnnounceTest < AirPlayOSTest
  def setup
    @d = AirPlayOS::MetadataDaemon.new(pipe: File.join(ROOT, "nonexistent-pipe"), run_dir: File.join(ROOT, "run/airplay-os-announce"))
  end

  def feed(type, code, data = "")
    @d.parser.feed(AirPlayOS::Metadata.encode_item(type, code, data)).each { |i| @d.parser.apply(i) }
  end

  # stderr lines emitted by announce after the given events, without the timestamp/level prefix
  def lines_after(*events)
    _out, err = capture_io { events.each { |(t, c, d)| feed(t, c, d || ""); @d.announce } }
    err.lines.map { |l| l.sub(/\A.*?\] [\w-]+: /, "").chomp }
  end

  def test_play_pause_track_change_and_stop
    assert_empty lines_after(%w[ssnc snam Flo's\ iPhone], %w[ssnc conn]), "a connection without a track is not a line"
    assert_equal ["⏵ Blue in Green — Miles Davis · Flo's iPhone"],
                 lines_after(%w[ssnc mdst], %w[core minm Blue\ in\ Green], %w[core asar Miles\ Davis], %w[ssnc mden], %w[ssnc pbeg])
    assert_equal ["⏸ Blue in Green — Miles Davis"], lines_after(%w[ssnc pfls])
    assert_equal ["⏵ Blue in Green — Miles Davis"], lines_after(%w[ssnc prsm]), "resume: client not repeated"
    assert_equal ["⏵ So What — Miles Davis"], lines_after(%w[ssnc mdst], %w[core minm So\ What], %w[ssnc mden])
    assert_equal ["⏹ Flo's iPhone"], lines_after(%w[ssnc pend])
    assert_empty lines_after(%w[ssnc pend]), "nothing to stop twice"
  end

  def test_playing_without_metadata_names_the_client
    assert_equal ["⏵ Flo's iPhone"], lines_after(%w[ssnc snam Flo's\ iPhone], %w[ssnc pbeg])
    assert_equal ["⏹ Flo's iPhone"], lines_after(%w[ssnc pend])
  end
end
