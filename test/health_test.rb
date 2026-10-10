# frozen_string_literal: true

require_relative "test_helper"

class HealthTest < AirPlayOSTest
  H = AirPlayOS::Health

  def setup
    mkdirs("sys/class/thermal/thermal_zone0", "proc")
    File.write(File.join(ROOT, "sys/class/thermal/thermal_zone0/temp"), "48234\n")
    File.write(File.join(ROOT, "proc/meminfo"), "MemTotal:        926512 kB\nMemFree:         210000 kB\nMemAvailable:    650000 kB\n")
    File.write(File.join(ROOT, "proc/stat"), "cpu  1000 0 500 8000 100 0 20 0 0 0\ncpu0 1000 0 500 8000 100 0 20 0 0 0\n")
  end

  def test_sample_and_line
    s = H.sample(interval: 0)
    assert s["ok"]
    assert_equal 48.2, s["temperature_c"]
    assert_equal 30, s["mem_percent"] # (926512 - 650000) / 926512
    assert_equal 0, s["cpu_percent"]  # two identical samples: no busy time
    assert_equal "cpu 0% · mem 30% · 48.2°C", H.line(s)
  end

  def test_cpu_busy_share_between_samples
    a = { idle: 8100, total: 9620 }
    File.write(File.join(ROOT, "proc/stat"), "cpu  1300 0 600 8200 100 0 20 0 0 0\n")
    b = H.cpu_times
    busy = 100.0 * ((b[:total] - a[:total]) - (b[:idle] - a[:idle])) / (b[:total] - a[:total])
    assert_in_delta 66.67, busy, 0.01 # Δtotal 600, Δidle 200
  end

  def test_degraded_when_hot_and_missing_sources
    File.write(File.join(ROOT, "sys/class/thermal/thermal_zone0/temp"), "85000\n")
    s = H.sample(interval: 0)
    refute s["ok"]
    assert_match(/\ADEGRADED · cpu .* · 85.0°C\z/, H.line(s))
    File.unlink(File.join(ROOT, "sys/class/thermal/thermal_zone0/temp"))
    s = H.sample(interval: 0)
    assert s["ok"]
    assert_nil s["temperature_c"]
    assert_match(/temp n\/a/, H.line(s))
  end
end
