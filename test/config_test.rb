# frozen_string_literal: true

require_relative "test_helper"

class ConfigTest < AirPlayOSTest
  C = AirPlayOS::Config

  def setup
    install_defaults
    File.unlink(AirPlayOS.path(:settings)) if File.exist?(AirPlayOS.path(:settings))
  end

  def test_paths_are_relocated
    assert_equal "#{ROOT}/etc/airplay-os/defaults.json", AirPlayOS.path(:defaults)
    assert_raises(ArgumentError) { AirPlayOS.path(:nope) }
  end

  def test_merge_deep
    assert_equal({ "a" => 2, "n" => { "x" => 1, "y" => 3 }, "l" => [2] },
                 C.merge_deep({ "a" => 1, "n" => { "x" => 1, "y" => 2 }, "l" => [1] }, { "a" => 2, "n" => { "y" => 3 }, "l" => [2] }))
    assert_equal({ "a" => 1 }, C.merge_deep(nil, { "a" => 1 }))
  end

  def test_json_round_trip_is_atomic
    assert_equal DEFAULTS, C.load_defaults
    assert_empty Dir.glob("#{ROOT}/etc/airplay-os/.*.tmp"), "no temp files left"
    assert_equal "644", format("%o", File.stat(AirPlayOS.path(:defaults)).mode & 0o777)
    spit("#{ROOT}/etc/airplay-os/bad.json", '{"a":')
    e = assert_raises(AirPlayOS::Error) { C.load_json("#{ROOT}/etc/airplay-os/bad.json") }
    assert_match(/invalid JSON/, e.message)
  end

  def test_missing_settings_is_empty_and_effective_equals_defaults
    assert_equal({}, C.load_settings)
    assert_equal DEFAULTS, C.effective_settings
  end

  def test_validation
    assert_empty C.validate_settings("name" => "Kitchen", "volume_max_db" => -3)
    e = C.validate_settings("name" => "", "interpolation" => "fast", "output_format" => "S24_LE",
                            "volume_max_db" => 1, "volume_range_db" => "x",
                            "bogus" => 1, "password" => 'a"b')
    joined = e.join("\n")
    assert_match(/name:/, joined)
    assert_match(/interpolation: must be one of/, joined)
    assert_match(/output_format: must be one of/, joined)
    assert_match(/volume_max_db: must be between -30 and 0/, joined)
    assert_match(/volume_range_db: must be a number/, joined)
    assert_match(/unknown setting 'bogus'/, joined)
    assert_match(/password:/, joined)
    assert_equal 7, e.size, "exactly one problem per bad key"
    assert_equal ["settings must be an object"], C.validate_settings([1])
  end

  def test_save_settings_stores_only_differences
    C.save_settings({ "name" => "Kitchen", "volume_max_db" => -6.0 }, defaults: DEFAULTS)
    assert_equal({ "name" => "Kitchen" }, C.load_settings)
    assert_equal "Kitchen", C.effective_settings["name"]
    assert_equal "auto", C.effective_settings["interpolation"]
    assert_raises(C::InvalidSettings) { C.save_settings({ "name" => "x" * 50 }, defaults: DEFAULTS) }
    assert_raises(C::InvalidSettings) { C.save_settings({ "pins" => {} }, defaults: DEFAULTS) }
  end

  def test_schema_exposed_for_the_ui
    schema = C.settings_schema
    assert_equal %w[interpolation name output_format password volume_max_db volume_range_db], schema.keys.sort
    assert_equal %w[auto vernier soxr basic], schema["interpolation"][:values]
  end

  def test_logger_writes_to_relocated_dir
    AirPlayOS::Log.init("t-config")
    AirPlayOS::Log.info("hello log")
    assert_match(/\[INFO\] t-config: hello log/, slurp("#{ROOT}/var/log/airplay-os/t-config.log"))
  end
end
