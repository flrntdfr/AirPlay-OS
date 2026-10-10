# frozen_string_literal: true

require_relative "test_helper"

class SettingsTest < AmpberryTest
  S = Ampberry::Settings

  def setup
    install_defaults
    File.unlink(Ampberry.path(:settings)) if File.exist?(Ampberry.path(:settings))
  end

  def test_render_defaults
    conf = S.render_conf(DEFAULTS)
    assert_match(/^general = \{\n  name = "Ampberry";\n  service_type = "airplay2";\n  interpolation = "auto";/m, conf)
    refute_match(/password/, conf)
    refute_match(/udp_port_base/, conf, "no AirPlay 1 port settings")
    assert_match(/^  volume_range_db = 60;\n  volume_max_db = -6\.0;/m, conf)
    assert_match(/^alsa = \{\n  output_device = "hw:0";\n  mixer_control_name = "Digital";\n  mixer_device = "hw:0";\n  output_format = "S32_LE";\n  output_rate = "auto";\n\};/m, conf)
    assert_includes conf, %(pipe_name = "#{ROOT}/run/shairport-sync/metadata";)
    assert_match(/allow_session_interruption = "yes";\n  session_timeout = 60;/, conf)
  end

  def test_render_custom_values
    c = S.render_conf(DEFAULTS.merge("name" => "Kitchen Amp", "password" => "p-w0rd!", "output_format" => "S16_LE",
                                     "volume_max_db" => -3, "interpolation" => "soxr"))
    assert_includes c, 'name = "Kitchen Amp";'
    assert_match(/^  password = "p-w0rd!";$/m, c)
    assert_includes c, 'output_format = "S16_LE";'
    assert_includes c, "volume_max_db = -3.0;", "integer dB gets a decimal point (required by shairport-sync)"
    assert_includes c, 'interpolation = "soxr";'
  end

  def test_render_rejects_invalid
    e = assert_raises(Ampberry::Config::InvalidSettings) { S.render_conf(DEFAULTS.merge("volume_max_db" => 5)) }
    assert_match(/volume_max_db/, e.message)
    assert_raises(Ampberry::Config::InvalidSettings) { S.render_conf(DEFAULTS.merge("name" => 'Kitchen "Amp"')) }
  end

  def test_write_conf_is_atomic
    S.write_conf(S.render_conf(DEFAULTS))
    assert File.size?(Ampberry.path(:shairport_conf))
    assert_empty Dir.glob("#{ROOT}/etc/.shairport-sync.conf.*")
  end

  def test_apply_persists_and_restarts
    with_runner(->(cmd, opts) { device_mock(cmd, opts) }) do
      eff = S.apply(settings: DEFAULTS.merge("name" => "Kitchen", "volume_max_db" => -9))
      assert_equal "Kitchen", eff["name"]
      assert_equal({ "name" => "Kitchen", "volume_max_db" => -9 }, Ampberry::Config.load_settings)
      assert_includes slurp(Ampberry.path(:shairport_conf)), "volume_max_db = -9.0;"
      assert_includes cmds, "systemctl enable --now nqptp"
      assert_includes cmds, "systemctl restart shairport-sync"
    end
    with_runner(->(cmd, opts) { device_mock(cmd, opts) }) do
      S.apply(settings: DEFAULTS)
      assert_equal({}, Ampberry::Config.load_settings, "back to defaults → empty settings.json")
    end
  end
end
