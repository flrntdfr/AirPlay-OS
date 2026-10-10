# frozen_string_literal: true

require_relative "test_helper"

# devices/<id>.json → /etc/airplay-os/device.json: what the tools derive from it.
class DeviceTest < AirPlayOSTest
  # the written definition must not leak into the other tests (the suite runs in random order)
  def teardown
    File.unlink(AirPlayOS.path(:device)) if File.exist?(AirPlayOS.path(:device))
    AirPlayOS.reset_device!
  end

  def write_device(hash)
    spit(AirPlayOS.path(:device), JSON.generate(hash))
    AirPlayOS.reset_device!
  end

  def test_missing_definition_means_the_original_ampberry
    File.unlink(AirPlayOS.path(:device)) if File.exist?(AirPlayOS.path(:device))
    AirPlayOS.reset_device!
    d = AirPlayOS.device
    assert_equal %w[ampberry Ampberry wlan0], [d["id"], d["pretty_name"], d["primary_interface"]]
    assert d["wifi"]
    assert_equal %w[dtparam=audio=off dtoverlay=hifiberry-dacplus-std dtparam=i2c_arm=on dtoverlay=disable-bt], AirPlayOS::System.config_txt_lines
  end

  def test_the_repo_definitions_are_consistent
    %w[ampberry hifiberry].each do |id|
      d = JSON.parse(File.read(File.expand_path("../docs/devices/#{id}.json", __dir__)))
      assert_equal id, d["id"]
      %w[hostname pretty_name description primary_interface address].each { |k| assert d[k].is_a?(String) && !d[k].empty?, "#{id}: #{k}" }
      assert_includes [true, false], d["wifi"]
      assert_equal %w[hotspotCidr lanCidrs wifiInterface], d["network"].keys.sort
      assert_equal %w[interpolation name output_format password volume_max_db volume_range_db], d["defaults"].keys.sort
      refute_empty AirPlayOS::Config.validate_settings(d["defaults"].merge("volume_max_db" => 99)), "the schema is applied to the defaults"
      assert_empty AirPlayOS::Config.validate_settings(d["defaults"]), "#{id}: defaults must pass the settings schema"
    end
  end

  def test_an_ethernet_only_device_switches_both_radios_off_and_keeps_eeprom_detection
    write_device("id" => "hifiberry", "pretty_name" => "HifiBerry", "overlay" => nil, "wifi" => false, "bluetooth" => false, "primary_interface" => "eth0")
    assert_equal %w[dtparam=audio=off dtparam=i2c_arm=on dtoverlay=disable-bt dtoverlay=disable-wifi], AirPlayOS::System.config_txt_lines
    assert_equal "HifiBerry", AirPlayOS.device["pretty_name"]
    assert_equal "hifiberry", AirPlayOS.device["id"]
  end
end
