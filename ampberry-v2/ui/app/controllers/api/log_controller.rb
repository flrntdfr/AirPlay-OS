# frozen_string_literal: true

module Api
  # The live appliance log behind every page: bytes of /var/log/ampberry.log after a given offset,
  # plus the redeploy state (so the UI can brighten the backdrop while a redeploy runs). Both are
  # world-readable files written by root-side services; nothing privileged happens here.
  class LogController < ActionController::API
    MAX_CHUNK = 64 * 1024

    def show
      path = Ampberry.path(:applog)
      from = params[:from].to_i.clamp(0, 2**40)
      chunk = String.new
      size = 0
      if File.file?(path)
        size = File.size(path)
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

    def redeploy_state
      st = JSON.parse(File.read(Ampberry.path(:redeploy_state)))
      st.slice("state", "started_at", "finished_at", "error")
    rescue Errno::ENOENT, JSON::ParserError
      { "state" => "idle" }
    end
  end
end
