# frozen_string_literal: true

require_relative "test_helper"

class ProvisionTest < AirPlayOSTest
  P = AirPlayOS::Provision

  def setup
    install_defaults
    mkdirs("boot/firmware", "etc/avahi", "home/pi")
    spit(AirPlayOS.path(:config_txt), "dtparam=audio=off\n[all]\ndtoverlay=hifiberry-dacplus-std\ndtparam=i2c_arm=on\ndtoverlay=disable-bt\n")
    FileUtils.cp(File.join(FIXTURES, "avahi-daemon.conf"), AirPlayOS.path(:avahi_conf))
    File.unlink(AirPlayOS.path(:need_reboot)) if File.exist?(AirPlayOS.path(:need_reboot))
  end

  def test_step_order
    assert_equal %w[config_txt system ssh settings services minimize wifi reboot], P.steps.map(&:first)
  end

  def test_full_run_on_a_connected_device
    with_runner(->(cmd, opts) { device_mock(cmd, opts) }) do
      r = P.run_all
      assert_equal({ "config_txt" => "ok", "system" => "ok", "ssh" => "ok", "settings" => "ok",
                     "services" => "ok", "minimize" => "ok", "wifi" => "connected", "reboot" => "not needed" }, r)
      assert_includes cmds, "sshd -t", "sshd config validated"
      assert_includes cmds, "systemctl reload-or-restart ssh"
      assert_includes slurp(AirPlayOS.path(:shairport_conf)), 'service_type = "airplay2"'
      assert_includes cmds, "systemctl enable --now nqptp"
      assert_includes cmds, "systemctl restart shairport-sync"
      assert_includes cmds, "systemctl enable --now airplay-os-firewall.service"
      assert_includes cmds, "systemctl enable --now airplay-os-ui.service"
      assert_includes cmds, "systemctl enable --now airplay-os-control.socket"
      assert_includes cmds, "systemctl enable --now airplay-os-wifi-fallback.timer"
      assert_includes cmds, "systemctl disable --now bluetooth"
      refute cmds.any? { |c| c.start_with?("systemctl reboot") }
      assert_match(/^use-ipv6=no$/m, slurp(AirPlayOS.path(:avahi_conf)))
      assert File.size?(AirPlayOS.path(:ui_secret))
    end
  end

  def test_failure_aborts_and_skip_works
    with_runner(->(cmd, opts) { cmd.join(" ") == "systemctl restart shairport-sync" ? { status: 1, err: "Job failed" } : device_mock(cmd, opts) }) do
      e = assert_raises(AirPlayOS::Error) { P.run_all }
      assert_match(/provision step 'settings' failed/, e.message)
      refute cmds.any? { |c| c.start_with?("systemctl enable --now airplay-os-ui") }, "later steps did not run"
    end
    with_runner(->(cmd, opts) { device_mock(cmd, opts) }) do
      r = P.run_all(skip: %w[minimize wifi])
      assert_equal "skipped", r["minimize"]
      refute cmds.any? { |c| c.start_with?("apt-get") }
    end
  end

  def test_reboot_when_config_txt_changed
    spit(AirPlayOS.path(:config_txt), "dtparam=audio=on\n")
    with_runner(->(cmd, opts) { device_mock(cmd, opts) }) do
      r = P.run_all(skip: %w[minimize wifi])
      assert_equal "rebooting", r["reboot"]
      assert_equal "systemctl reboot", cmds.last
      refute File.exist?(AirPlayOS.path(:need_reboot))
    end
  end
end
