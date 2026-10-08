# frozen_string_literal: true

require_relative "test_helper"

class SystemTest < AmpberryTest
  S = Ampberry::System

  def setup
    install_defaults
    mkdirs("boot/firmware", "etc/avahi", "home/pi/.config/systemd/user/default.target.wants", "home/pi/.shairport",
           "etc/apt/sources.list.d", "usr/share/keyrings")
    File.unlink(Ampberry.path(:need_reboot)) if File.exist?(Ampberry.path(:need_reboot))
  end

  def test_config_txt_adds_only_missing_lines_under_all
    cfg = Ampberry.path(:config_txt)
    spit(cfg, "dtparam=audio=off\ncamera_auto_detect=1\n[cm4]\notg_mode=1\n[all]\nenable_uart=1\ndtparam=i2c_arm=on\ndtparam=spi=on\ndtoverlay=hifiberry-dacplus-std\n")
    r = S.ensure_config_txt
    assert r["changed"]
    assert_equal ["dtoverlay=disable-bt"], r["added"]
    assert_match(/dtoverlay=hifiberry-dacplus-std\n\n# Ampberry v2[^\n]*\ndtoverlay=disable-bt\n\z/, slurp(cfg))
    assert S.needs_reboot?
    File.unlink(Ampberry.path(:need_reboot))
    assert_equal({ "changed" => false, "added" => [] }, S.ensure_config_txt)
    refute S.needs_reboot?
  end

  def test_config_txt_stock_image
    cfg = Ampberry.path(:config_txt)
    spit(cfg, "dtparam=audio=on\n[cm5]\ndtoverlay=dwc2\n")
    r = S.ensure_config_txt
    assert_equal 4, r["added"].size
    assert_match(/^#dtparam=audio=on/m, slurp(cfg))
    assert_match(/\[cm5\]\ndtoverlay=dwc2\n\n\[all\]\n# Ampberry v2/, slurp(cfg), "new [all] section because last section was [cm5]")
  end

  def test_config_txt_dry_run
    cfg = Ampberry.path(:config_txt)
    spit(cfg, "x=1\n")
    Ampberry::Run.dry_run = true
    r = S.ensure_config_txt
    assert r["changed"] && r["dry_run"]
    assert_equal "x=1\n", slurp(cfg)
  ensure
    Ampberry::Run.dry_run = false
  end

  def test_avahi_ipv4_only
    FileUtils.cp(File.join(FIXTURES, "avahi-daemon.conf"), Ampberry.path(:avahi_conf))
    with_runner(->(_c, _o) { { status: 0, out: "active" } }) do
      assert S.ensure_avahi_ipv4["changed"]
      txt = slurp(Ampberry.path(:avahi_conf))
      assert_match(/^\[server\]\n(?:.*\n)*?use-ipv6=no\n/m, txt)
      assert_match(/^\[publish\]\n(?:.*\n)*?publish-aaaa-on-ipv4=no\n/m, txt)
      assert_match(/^publish-workstation=no$/m, txt)
      refute_match(/^use-ipv6=yes/m, txt)
      assert_match(/^use-ipv4=yes$/m, txt, "unrelated keys untouched")
      assert_includes cmds, "systemctl restart avahi-daemon"
      assert_equal({ "changed" => false }, S.ensure_avahi_ipv4)
    end
  end

  def test_minimize
    spit(Ampberry.path(:hifiberry_list), "deb http://debianrepo.hifiberry.com trixie main\n")
    spit(Ampberry.path(:hifiberry_key), "key")
    spit(Ampberry.path(:hifiberry_user), "pi\n")
    spit("#{ROOT}/home/pi/.config/systemd/user/default.target.wants/shairport.service", "")
    spit("#{ROOT}/home/pi/.shairport/shairport-sync.conf", "")
    handler = lambda do |cmd, _o|
      case cmd.first
      when "dpkg-query" then { status: 0, out: "hifiberry-webui\tinstalled\nhbos-full\tinstalled\npipewire\tnot-installed\nrpi-connect-lite\tinstalled\n" }
      when "loginctl" then cmd[1] == "show-user" ? { status: 0, out: "yes\n" } : { status: 0 }
      else { status: 0, out: "" }
      end
    end
    with_runner(handler) do
      m = S.minimize
      assert_equal %w[hifiberry-webui hbos-full rpi-connect-lite], m["purged"]
      assert_includes cmds, "apt-get -y purge hifiberry-webui hbos-full rpi-connect-lite"
      assert_includes cmds, "apt-get update"
      assert_includes cmds, "apt-get -y autoremove --purge"
      assert_includes cmds, "systemctl disable --now bluetooth"
      assert_includes cmds, "loginctl disable-linger pi"
      assert_equal 2, m["removed_sources"]
      refute File.exist?(Ampberry.path(:hifiberry_list))
      refute File.exist?(Ampberry.path(:hifiberry_user))
      refute File.exist?("#{ROOT}/home/pi/.shairport")
      assert_equal 3, m["residue"].size
    end
  end

  def test_clean_reboot
    Ampberry::Config.save_json_atomic(Ampberry.path(:settings), { "name" => "Kitchen" })
    with_runner(->(_c, _o) { { status: 0 } }) do
      S.clean_reboot(reset_settings: false)
      assert_equal ["cloud-init clean --logs", "sync", "systemctl reboot"], cmds
      assert File.exist?(Ampberry.path(:settings))
    end
    with_runner(->(_c, _o) { { status: 0 } }) do
      S.clean_reboot(reset_settings: true, no_reboot: true)
      refute File.exist?(Ampberry.path(:settings))
      assert_equal ["cloud-init clean --logs", "sync"], cmds
    end
  end

  def test_ui_secret_is_generated_once
    File.unlink(Ampberry.path(:ui_secret)) if File.exist?(Ampberry.path(:ui_secret))
    assert S.ensure_ui_secret
    first = slurp(Ampberry.path(:ui_secret))
    assert_operator first.strip.length, :>=, 64
    assert_equal "640", format("%o", File.stat(Ampberry.path(:ui_secret)).mode & 0o777)
    refute S.ensure_ui_secret
    assert_equal first, slurp(Ampberry.path(:ui_secret))
  end
end
