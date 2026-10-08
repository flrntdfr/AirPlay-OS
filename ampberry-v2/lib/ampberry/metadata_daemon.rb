# frozen_string_literal: true

require "json"
require "fileutils"

module Ampberry
  # Long-running reader of the shairport-sync metadata pipe. Publishes the now-playing state for
  # the web UI as plain files, so the UI needs no pipe handling at all:
  #   /run/ampberry/now-playing.json   JSON snapshot (atomically replaced on every change)
  #   /run/ampberry/cover-<sha1>.<ext> current cover art, referenced from the JSON
  # Exactly one reader may consume a FIFO; this daemon is it. The pipe is reopened whenever the
  # writer (shairport-sync) restarts.
  class MetadataDaemon
    POLL_INTERVAL = 0.25
    HEARTBEAT = 5

    def initialize(pipe: Ampberry.path(:metadata_pipe), run_dir: Ampberry.path(:run_dir))
      @pipe = pipe
      @run_dir = run_dir
      @parser = Metadata.new
      @cover_file = nil
      @last_write = 0.0
      @stop = false
    end

    attr_reader :parser

    def run(max_iterations: nil)
      %w[TERM INT].each { |s| trap(s) { @stop = true } }
      Log.info("metadata daemon: pipe #{@pipe} → #{@run_dir}")
      publish(force: true)
      n = 0
      until @stop
        break if max_iterations && (n += 1) > max_iterations

        fh = open_pipe
        unless fh
          sleep 1
          publish
          next
        end
        begin
          until @stop
            break if max_iterations && (n += 1) > max_iterations

            ready, = IO.select([fh], nil, nil, POLL_INTERVAL)
            if ready
              begin
                chunk = fh.read_nonblock(65_536)
              rescue IO::WaitReadable
                chunk = nil
              rescue EOFError
                break # writer closed: reopen
              end
              if chunk
                changed = @parser.feed(chunk).count { |item| @parser.apply(item) }
                if changed.positive?
                  publish(force: true)
                  announce
                end
              end
            end
            publish
          end
        ensure
          fh.close
        end
      end
      publish(force: true)
      true
    end

    # Write the snapshot (and cover) when something changed or the heartbeat is due.
    def publish(force: false, now: Time.now.to_f)
      playing = @parser.state["playing"]
      due = force || (playing && now - @last_write >= 1) || now - @last_write >= HEARTBEAT
      return false unless due

      FileUtils.mkdir_p(@run_dir)
      snap = @parser.snapshot(now)
      cover = @parser.state["cover"]
      if cover
        ext = { "image/png" => "png", "image/jpeg" => "jpg" }.fetch(cover["mime"], "bin")
        file = "cover-#{cover['sha1']}.#{ext}"
        if @cover_file != file
          write_atomic(File.join(@run_dir, file), cover["bytes"])
          old = @cover_file && File.join(@run_dir, @cover_file)
          File.unlink(old) if old && File.exist?(old)
          @cover_file = file
        end
        snap["cover_file"] = file
      else
        if @cover_file
          old = File.join(@run_dir, @cover_file)
          File.unlink(old) if File.exist?(old)
          @cover_file = nil
        end
        snap["cover_file"] = nil
      end
      snap["generated_at"] = now
      write_atomic(File.join(@run_dir, "now-playing.json"), JSON.generate(snap))
      @last_write = now
      true
    end

    # One journal line per meaningful change (feeds the live log behind the UI).
    def announce
      st = @parser.state
      key = [st["active"], st["playing"], st["title"], st["artist"], st["client"]]
      return if key == @announced

      @announced = key
      if !st["active"]
        Log.info("■ stopped")
      elsif st["title"].to_s.empty?
        Log.info("● #{st['client'].to_s.empty? ? 'AirPlay' : st['client']} connected")
      else
        Log.info("#{st['playing'] ? '▶' : '❙❙'} #{st['title']}#{st['artist'].to_s.empty? ? '' : " — #{st['artist']}"}#{st['client'].to_s.empty? ? '' : " (#{st['client']})"}")
      end
    end

    private

    def open_pipe
      return nil unless File.exist?(@pipe) && File.pipe?(@pipe) # shairport-sync creates the FIFO

      File.open(@pipe, File::RDONLY | File::NONBLOCK)
    rescue SystemCallError => e
      Log.warning("open #{@pipe}: #{e.message}")
      nil
    end

    def write_atomic(path, bytes)
      tmp = "#{path}.tmp.#{Process.pid}"
      File.binwrite(tmp, bytes)
      File.chmod(0o644, tmp)
      File.rename(tmp, path)
    end
  end
end
