# frozen_string_literal: true

module AirPlayOS
  # The quarter-hourly appliance health line for the live log (airplay-os-health.timer, on the clock):
  #   cpu 3% · mem 29% · 48.2°C          (DEGRADED · … when hot or out of memory)
  # Reads /sys and /proc only — no privilege, no external commands.
  module Health
    TEMP_WARN_C = 80.0
    MEM_WARN_PCT = 95.0

    class << self
      def sample(interval: 0.5)
        cpu = cpu_percent(interval)
        mem = mem_percent
        temp = temperature_c
        ok = (temp.nil? || temp < TEMP_WARN_C) && (mem.nil? || mem < MEM_WARN_PCT)
        { "ok" => ok, "temperature_c" => temp&.round(1), "cpu_percent" => cpu&.round, "mem_percent" => mem&.round }
      end

      def line(s)
        [
          ("DEGRADED" unless s["ok"]), # a healthy line starts straight with the numbers
          "cpu #{s["cpu_percent"] ? "#{s["cpu_percent"]}%" : "n/a"}",
          "mem #{s["mem_percent"] ? "#{s["mem_percent"]}%" : "n/a"}",
          s["temperature_c"] ? "#{s["temperature_c"]}°C" : "temp n/a"
        ].compact.join(" · ")
      end

      def temperature_c
        File.read(File.join(AirPlayOS.root, "/sys/class/thermal/thermal_zone0/temp")).to_i / 1000.0
      rescue SystemCallError
        nil
      end

      def mem_percent
        info = File.read(File.join(AirPlayOS.root, "/proc/meminfo"))
        total = info[/^MemTotal:\s+(\d+)/, 1].to_f
        avail = info[/^MemAvailable:\s+(\d+)/, 1].to_f
        return nil unless total.positive?

        100.0 * (total - avail) / total
      rescue SystemCallError
        nil
      end

      # Busy share of all CPUs over `interval` seconds (two /proc/stat samples).
      def cpu_percent(interval)
        a = cpu_times
        sleep(interval) if interval.positive?
        b = cpu_times
        return nil unless a && b

        idle = b[:idle] - a[:idle]
        total = b[:total] - a[:total]
        total.positive? ? 100.0 * (total - idle) / total : 0.0
      end

      def cpu_times
        line = File.read(File.join(AirPlayOS.root, "/proc/stat")).lines.find { |l| l.start_with?("cpu ") }
        return nil unless line

        f = line.split[1..].map(&:to_i)
        { idle: f[3] + (f[4] || 0), total: f.sum }
      rescue SystemCallError
        nil
      end
    end
  end
end
