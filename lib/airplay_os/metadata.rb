# frozen_string_literal: true

require "digest/sha1"

module Ampberry
  # Incremental parser for the shairport-sync metadata pipe and the now-playing state it feeds.
  # No I/O: feed() bytes in, items out; apply() folds items into the state.
  #
  # Pipe format (items may be split arbitrarily across reads):
  #   <item><type>73736e63</type><code>70626567</code><length>0</length></item>
  #   <item><type>636f7265</type><code>6d696e6d</code><length>5</length>
  #   <data encoding="base64">
  #   SGVsbG8=</data></item>
  # type/code are 4-ASCII-character tags as 8 hex digits: "ssnc" (shairport) / "core" (DMAP).
  class Metadata
    RTP_RATE = 44_100
    MAX_BUFFER = 8 * 1024 * 1024
    MAX_COVER = 2 * 1024 * 1024

    CORE = { "minm" => "title", "asar" => "artist", "asal" => "album", "asgn" => "genre",
             "ascp" => "composer", "asaa" => "album_artist" }.freeze

    ITEM_RE = %r{\A\s*<item><type>([0-9a-fA-F]{8})</type><code>([0-9a-fA-F]{8})</code><length>(\d+)</length>(?:\s*<data encoding="base64">\s*([A-Za-z0-9+/=\s]*?)</data>)?\s*</item>}m

    Item = Struct.new(:type, :code, :length, :data)

    attr_reader :state

    def initialize
      @buf = String.new(encoding: Encoding::BINARY)
      @pending = nil
      @state = idle_state
      @max_cover = MAX_COVER
    end

    attr_accessor :max_cover

    # Feed raw bytes; returns the complete items parsed.
    def feed(bytes)
      @buf << bytes.b
      items = []
      while (m = ITEM_RE.match(@buf))
        @buf = @buf[m.end(0)..] || String.new(encoding: Encoding::BINARY)
        data = m[4] ? m[4].unpack1("m") : ""
        items << Item.new([m[1]].pack("H*"), [m[2]].pack("H*"), m[3].to_i, data)
      end
      if @buf.bytesize > MAX_BUFFER
        i = @buf.index("<item>", 1)
        @buf = i ? @buf[i..] : String.new(encoding: Encoding::BINARY)
      elsif !@buf.include?("<") && @buf.match?(/\S/)
        @buf = String.new(encoding: Encoding::BINARY) # junk without any tag start: discard
      end
      items
    end

    # Fold one item into the state; returns true when the visible state changed.
    # Between mdst and mden, core updates are buffered and committed atomically on mden.
    def apply(item)
      changed = case item.type
                when "core" then apply_core(item)
                when "ssnc" then apply_ssnc(item)
                else false
                end
      @state["updated_at"] = Time.now.to_f if changed
      changed
    end

    # Playback position, extrapolated from the last progress report while playing.
    def position(now = Time.now.to_f)
      p = @state["progress"] or return nil
      pos = p["position_s"] + (@state["playing"] ? now - p["received_at"] : 0)
      pos = p["duration_s"] if p["duration_s"]&.positive? && pos > p["duration_s"]
      pos
    end

    # JSON-friendly snapshot (no cover bytes; the cover is referenced by sha1).
    def snapshot(now = Time.now.to_f)
      s = @state
      {
        "playing" => s["playing"], "active" => s["active"],
        "title" => s["title"], "artist" => s["artist"], "album" => s["album"], "genre" => s["genre"],
        "client" => s["client"], "updated_at" => s["updated_at"],
        # remote control of the sender (play/pause): see Ampberry::Remote
        "dacp_id" => s["dacp_id"], "active_remote" => s["active_remote"],
        "duration_s" => s["progress"] ? s["progress"]["duration_s"] : (s["duration_ms"] ? s["duration_ms"] / 1000.0 : nil),
        "position_s" => position(now),
        "volume" => s["volume"],
        "cover" => s["cover"] && { "sha1" => s["cover"]["sha1"], "mime" => s["cover"]["mime"], "size" => s["cover"]["size"] }
      }
    end

    # Test/tool helper: encode one pipe item.
    def self.encode_item(type, code, data = "")
      head = format("<item><type>%s</type><code>%s</code><length>%d</length>", type.unpack1("H*"), code.unpack1("H*"), data.bytesize)
      return "#{head}</item>\n" if data.empty?

      "#{head}\n<data encoding=\"base64\">\n#{[data].pack('m0')}</data></item>\n"
    end

    private

    def idle_state
      { "playing" => false, "active" => false, "title" => "", "artist" => "", "album" => "", "genre" => "",
        "client" => "", "client_ip" => "", "volume" => nil, "progress" => nil, "cover" => nil,
        "duration_ms" => nil, "dacp_id" => "", "active_remote" => "", "updated_at" => 0 }
    end

    def utf8(bytes)
      s = bytes.dup.force_encoding(Encoding::UTF_8)
      s.valid_encoding? ? s : bytes.dup.force_encoding(Encoding::BINARY).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end

    def apply_core(item)
      if (field = CORE[item.code])
        text = utf8(item.data)
        if @pending
          @pending[field] = text
          return false
        end
        return false if @state[field] == text

        @state[field] = text
        return true
      end
      if item.code == "astm" && item.data.bytesize >= 4
        ms = item.data[-4..].unpack1("N")
        if @pending
          @pending["duration_ms"] = ms
          return false
        end
        @state["duration_ms"] = ms
        return true
      end
      false
    end

    def apply_ssnc(item)
      st = @state
      case item.code
      when "mdst"
        @pending = {}
        false
      when "mden"
        p = @pending
        @pending = nil
        return false unless p

        changed = false
        p.each do |k, v|
          next if st[k] == v

          st[k] = v
          changed = true
        end
        changed
      when "PICT"
        apply_cover(item.data)
      when "pbeg", "prsm"
        changed = !st["playing"] || !st["active"]
        st["playing"] = true
        st["active"] = true
        changed
      when "pend"
        keep = st.slice("client", "client_ip", "volume")
        @state = idle_state.merge(keep)
        @pending = nil
        true
      when "pfls"
        changed = st["playing"]
        st["playing"] = false
        changed
      when "prgr"
        start, cur, fin = utf8(item.data).split("/").map(&:to_i)
        return false unless fin

        cur += 2**32 if cur < start
        fin += 2**32 if fin < start
        st["progress"] = { "start" => start, "current" => cur, "end" => fin,
                           "position_s" => (cur - start) / RTP_RATE.to_f,
                           "duration_s" => (fin - start) / RTP_RATE.to_f,
                           "received_at" => Time.now.to_f }
        true
      when "pvol"
        airplay, db, lo, hi = utf8(item.data).split(",").map(&:to_f)
        st["volume"] = { "airplay" => airplay, "db" => db, "min_db" => lo, "max_db" => hi }
        true
      when "snam"
        v = utf8(item.data)
        changed = st["client"] != v
        st["client"] = v
        st["active"] = true
        changed
      when "clip"
        v = utf8(item.data)
        changed = st["client_ip"] != v
        st["client_ip"] = v
        changed
      when "daid", "acre" # DACP id / Active-Remote token: what a remote command needs
        key = item.code == "daid" ? "dacp_id" : "active_remote"
        v = utf8(item.data).strip
        changed = st[key] != v
        st[key] = v
        changed
      when "conn"
        changed = !st["active"]
        st["active"] = true
        changed
      when "disc"
        @state = idle_state
        @pending = nil
        true
      else
        false
      end
    end

    def apply_cover(data)
      st = @state
      if data.empty?
        return false unless st["cover"]

        st["cover"] = nil
        return true
      end
      return false if data.bytesize > @max_cover

      mime = if data.byteslice(0, 3) == "\xFF\xD8\xFF".b then "image/jpeg"
             elsif data.byteslice(0, 8) == "\x89PNG\r\n\x1a\n".b then "image/png"
             else "application/octet-stream"
             end
      sha = Digest::SHA1.hexdigest(data)
      return false if st["cover"] && st["cover"]["sha1"] == sha

      st["cover"] = { "bytes" => data, "mime" => mime, "sha1" => sha, "size" => data.bytesize }
      true
    end
  end
end
