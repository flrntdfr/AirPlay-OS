# frozen_string_literal: true

require_relative "test_helper"

# devices/<id>.json → /etc/ampberry/device.json: what the tools derive from it.
class DeviceTest < AmpberryTest
  def teardown = Ampberry.reset_device!

  def write_device(hash)
    spit(Ampberry.path(:device), JSON.generate(hash))
    Ampberry.reset_device!
  end

  def test_missing_definition_means_the_original_ampberry
    File.unlink(Ampberry.path(:device)) if File.exist?(Ampberry.path(:device))
    Ampberry.reset_device!
    d = Ampberry.device
    assert_equal %w[ampberry Ampberry wlan0], [d["id"], d["pretty_name"], d["primary_interface"]]
    assert d["wifi"]
    assert_equal %w[dtparam=audio=off dtoverlay=hifiberry-dacplus-std dtparam=i2c_arm=on dtoverlay=disable-bt], Ampberry::System.config_txt_lines
  end

  def test_the_repo_definitions_are_consistent
    %w[ampberry hifiberry].each do |id|
      d = JSON.parse(File.read(File.expand_path("../devices/#{id}.json", __dir__)))
      assert_equal id, d["id"]
      %w[hostname pretty_name description primary_interface address].each { |k| assert d[k].is_a?(String) && !d[k].empty?, "#{id}: #{k}" }
      assert_includes [true, false], d["wifi"]
      assert_equal %w[hotspotCidr lanCidrs wifiInterface], d["network"].keys.sort
      assert_equal %w[interpolation name output_format password volume_max_db volume_range_db], d["defaults"].keys.sort
      refute_empty Ampberry::Config.validate_settings(d["defaults"].merge("volume_max_db" => 99)), "the schema is applied to the defaults"
      assert_empty Ampberry::Config.validate_settings(d["defaults"]), "#{id}: defaults must pass the settings schema"
    end
  end

  def test_an_ethernet_only_device_switches_both_radios_off_and_keeps_eeprom_detection
    write_device("id" => "hifiberry", "pretty_name" => "HifiBerry", "overlay" => nil, "wifi" => false, "bluetooth" => false, "primary_interface" => "eth0")
    assert_equal %w[dtparam=audio=off dtparam=i2c_arm=on dtoverlay=disable-bt dtoverlay=disable-wifi], Ampberry::System.config_txt_lines
    assert_equal "HifiBerry", Ampberry.device["pretty_name"]
    assert_equal "hifiberry", Ampberry.device["id"]
  end
end
