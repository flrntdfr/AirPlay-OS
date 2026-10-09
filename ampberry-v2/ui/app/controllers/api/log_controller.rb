# frozen_string_literal: true

module Api
  # The live appliance log behind every page: bytes of /var/log/ampberry.log after a given offset,
  # plus the redeploy state (so the UI can brighten the backdrop while a redeploy runs). Both are
  # world-readable files written by root-side services; nothing privileged happens here.
  #   GET /api/log?tail=100   the last 100 lines (what a page loads first)
  #   GET /api/log?from=N     everything written since byte N (what it polls afterwards)
  class LogController < ActionController::API
    MAX_CHUNK = 64 * 1024
    MAX_TAIL = 500

    def show
      path = Ampberry.path(:applog)
      chunk = String.new
      size = 0
      from = params[:from].to_i.clamp(0, 2**40)
      if File.file?(path)
        size = File.size(path)
        from = tail_offset(path, size, params[:tail].to_i.clamp(1, MAX_TAIL)) if params.key?(:tail)
        from = 0 if from > size # rotated/truncated: start over
        File.open(path, "rb") do |f|
          f.seek(from)
          chunk = f.read(MAX_CHUNK) || String.new
        end
      end
      render json: { "from" => from, "to" => from + chunk.bytesize, "size" => size,
                     "chunk" => chunk.dup.force_encoding("UTF-8").scrub, "redeploy" => redeploy_state }
    end

    private

    # Byte offset of the start of the last `lines` lines (reads backwards, at most MAX_CHUNK).
    def tail_offset(path, size, lines)
      start = [size - MAX_CHUNK, 0].max
      data = File.open(path, "rb") { |f| f.seek(start); f.read(size - start) || String.new }
      data = data.chomp("\n")
      pos = data.bytesize
      lines.times do
        nl = data.byterindex("\n", pos - 1) if pos.positive?
        return start if nl.nil?

        pos = nl
      end
      start + pos + 1
    end

    def redeploy_state
      st = JSON.parse(File.read(Ampberry.path(:redeploy_state)))
      st.slice("state", "started_at", "finished_at", "error")
    rescue Errno::ENOENT, JSON::ParserError
      { "state" => "idle" }
    end
  end
end
