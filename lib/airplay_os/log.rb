# frozen_string_literal: true

module AirPlayOS
  # Timestamped lines to STDERR (journald / cloud-init capture them; STDOUT stays free for data —
  # the control handler's STDOUT *is* the client socket) and, when the log directory exists and is
  # writable, appended to /var/log/airplay-os/<name>.log.
  module Log
    class << self
      attr_reader :name

      def init(name, verbose: ENV["AIRPLAY_OS_DEBUG"].to_s == "1", dir: nil)
        @name = name
        @verbose = verbose
        $stderr.sync = true
        @file&.close
        @file = nil
        dir ||= AirPlayOS.path(:log)
        if File.directory?(dir) && File.writable?(dir)
          @file = File.open(File.join(dir, "#{name}.log"), "a")
          @file.sync = true
        end
        AirPlayOS::Run.logger = ->(msg) { debug(msg) }
        nil
      end

      def info(msg) = emit("INFO", msg)
      def warning(msg) = emit("WARN", msg)
      def error(msg) = emit("ERROR", msg)
      def debug(msg) = emit("DEBUG", msg)

      private

      def emit(level, msg)
        line = format("%s [%s] %s: %s\n", Time.now.strftime("%Y-%m-%dT%H:%M:%S%z"), level, @name || "airplay-os", msg.to_s.rstrip)
        $stderr.print(line) unless level == "DEBUG" && !@verbose
        @file&.print(line)
        nil
      end
    end
  end
end
