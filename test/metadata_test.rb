# frozen_string_literal: true

require_relative "test_helper"

class MetadataTest < AmpberryTest
  M = Ampberry::Metadata

  def item(type, code, data = "") = M.encode_item(type, code, data)

  def test_framing_split_reads_and_no_data
    m = M.new
    items = m.feed(item("ssnc", "pbeg"))
    assert_equal 1, items.size
    assert_equal %w[ssnc pbeg], [items[0].type, items[0].code]
    assert_equal "", items[0].data

    title = item("core", "minm", "Hello Wörld")
    assert_empty m.feed(title[0, 20])
    assert_empty m.feed(title[20, 30])
    t = m.feed(title[50..]).first
    assert_equal "minm", t.code
    assert_equal "Hello Wörld".b, t.data
    assert_equal 3, m.feed(item("core", "asar", "Artist") + item("core", "asal", "Album") + item("ssnc", "mden")).size
  end

  def test_real_world_framing
    raw = %(<item><type>73736e63</type><code>70726772</code><length>33</length>\n<data encoding="base64">\nMjM3MzkyNTgxOC8yMzczOTQxMTc4LzIzODUwODEzNTQ=</data></item>\n)
    p = M.new.feed(raw).first
    assert_equal %w[ssnc prgr], [p.type, p.code]
    assert_equal "2373925818/2373941178/2385081354", p.data
  end

  def test_state_machine
    s = M.new
    run = ->(*raw) { s.feed(raw.join).sum { |i| s.apply(i) ? 1 : 0 } }

    run.call(item("ssnc", "snam", "Flo's iPhone"), item("ssnc", "clip", "192.168.178.40"))
    assert_equal "Flo's iPhone", s.state["client"]
    assert s.state["active"]
    refute s.state["playing"]

    run.call(item("ssnc", "mdst", "12345"))
    assert_equal 0, run.call(item("core", "minm", "Track One"), item("core", "asar", "Band"), item("core", "asal", "LP")), "no visible change inside a bundle"
    assert_equal "", s.state["title"]
    assert_equal 1, run.call(item("ssnc", "mden", "12345")), "mden commits atomically"
    assert_equal %w[Track\ One Band LP], s.state.values_at("title", "artist", "album")

    assert_equal 1, run.call(item("ssnc", "pbeg"))
    assert s.state["playing"]

    start = 2_373_925_818
    run.call(item("ssnc", "prgr", "#{start}/#{start + 44_100 * 30}/#{start + 44_100 * 200}"))
    assert_in_delta 200, s.state["progress"]["duration_s"]
    assert_in_delta 30, s.state["progress"]["position_s"]
    now = s.state["progress"]["received_at"]
    assert_in_delta 40, s.position(now + 10)
    assert_in_delta 200, s.position(now + 1000), 0.001, "clamped at duration"

    run.call(item("ssnc", "pfls"))
    refute s.state["playing"]
    assert_in_delta 30, s.position(now + 10), 0.001, "frozen while paused"
    run.call(item("ssnc", "prsm"))
    assert s.state["playing"]

    wrap = 4_294_967_000
    run.call(item("ssnc", "prgr", [wrap, wrap + 44_100 * 5 - 2**32, wrap + 44_100 * 60 - 2**32].join("/")))
    assert_in_delta 60, s.state["progress"]["duration_s"]
    assert_in_delta 5, s.state["progress"]["position_s"]

    run.call(item("ssnc", "pvol", "-15.00,-23.50,-60.00,-6.00"))
    assert_equal({ "airplay" => -15.0, "db" => -23.5, "min_db" => -60.0, "max_db" => -6.0 }, s.state["volume"])

    jpeg = "\xFF\xD8\xFF\xE0".b + ("x" * 100)
    assert_equal 1, run.call(item("ssnc", "PICT", jpeg))
    assert_equal "image/jpeg", s.state["cover"]["mime"]
    assert_equal 104, s.state["cover"]["size"]
    assert_equal 0, run.call(item("ssnc", "PICT", jpeg)), "identical cover is not a change"
    run.call(item("ssnc", "PICT", "\x89PNG\r\n\x1a\n".b + ("y" * 10)))
    assert_equal "image/png", s.state["cover"]["mime"]
    s.max_cover = 50
    run.call(item("ssnc", "PICT", "z" * 60))
    assert_equal "image/png", s.state["cover"]["mime"], "oversized cover ignored"

    snap = s.snapshot(now + 1)
    assert_equal "Track One", snap["title"]
    refute snap["cover"].key?("bytes")
    assert_equal "image/png", snap["cover"]["mime"]
    assert snap["position_s"]

    assert_equal 1, run.call(item("ssnc", "pend"))
    refute s.state["playing"] || s.state["active"]
    assert_equal "", s.state["title"]
    assert_equal "Flo's iPhone", s.state["client"], "client kept across pend"
    run.call(item("ssnc", "disc"))
    assert_equal "", s.state["client"]

    assert_equal 1, run.call(item("core", "minm", "Direct"))
    assert_equal "Direct", s.state["title"]
    run.call(item("core", "astm", [185_000].pack("N")))
    assert_in_delta 185, s.snapshot["duration_s"]
  end

  def test_garbage_resilience
    g = M.new
    assert_empty g.feed("garbage without items\n")
    assert_equal 1, g.feed(item("ssnc", "pbeg")).size
  end
end
