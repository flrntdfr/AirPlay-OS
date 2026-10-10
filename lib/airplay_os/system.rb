# frozen_string_literal: true

require "etc"
require "fileutils"
require "securerandom"
require "tempfile"

module AirPlayOS
  # Host-level idempotent steps the flake cannot express: boot config, users/dirs, dpkg-owned
  # config files (avahi), hostname, HiFiBerry OS leftovers, and the "clean reboot".
  module System
    UI_USER = "airplay-os"
    AUDIO_USER = "shairport-sync"
    LEFTOVER_PATTERNS = %w[hifiberry-* hbos-* pipewire* wireplumber rpi-connect-lite pipewire-api ladspa-speakereq ladspa-riaa].freeze

    class << self
      def root? = Process.uid.zero?
      def dry? = AirPlayOS::Run.dry_run ? true : false

      def mark_need_reboot
        FileUtils.touch(AirPlayOS.path(:need_reboot)) unless dry?
      end

      def needs_reboot? = File.exist?(AirPlayOS.path(:need_reboot))

      # ---- /boot/firmware/config.txt -------------------------------------------------------

      # Ensure the HAT lines are present (appended under a trailing [all] section when missing) and
      # that the onboard audio is not re-enabled. Returns { "changed" => bool, "added" => [...] }.
      # /boot/firmware/config.txt lines for this device (docs/devices/<id>.json): onboard audio off,
      # the HAT overlay (none when the HAT's EEPROM is left to announce it), I2C for the DAC,
      # and each radio the device does not use switched off at the device-tree level.
      def config_txt_lines(device = AirPlayOS.device)
        lines = ["dtparam=audio=off"]
        lines << "dtoverlay=#{device['overlay']}" if device["overlay"].is_a?(String) && !device["overlay"].empty?
        lines << "dtparam=i2c_arm=on"
        lines << "dtoverlay=disable-bt" unless device["bluetooth"]
        lines << "dtoverlay=disable-wifi" unless device["wifi"]
        lines
      end

      def ensure_config_txt(path: AirPlayOS.path(:config_txt), lines: config_txt_lines)
        content = File.read(path).lines.map(&:chomp)
        have = content.reject { |l| l.match?(/\A\s*#/) }.map(&:strip)
        missing = lines - have
        changed = false
        content.map! do |l|
          if l.match?(/\A\s*dtparam=audio=on\s*\z/)
            changed = true
            "##{l}   # disabled by airplay-os: the HiFiBerry HAT is the audio device"
          else
            l
          end
        end
        unless missing.empty?
          last_section = content.reverse.find { |l| l.match?(/\A\s*\[/) }
          content << "" if content.any? && content.last != ""
          content << "[all]" if last_section && !last_section.match?(/\A\s*\[all\]\s*\z/)
          content << "# AirPlay OS v2 (HiFiBerry Amp2, Bluetooth off)"
          content.concat(missing)
          changed = true
        end
        return { "changed" => false, "added" => [] } unless changed

        Log.info("config.txt: adding #{missing.join(', ')}") unless missing.empty?
        return { "changed" => true, "added" => missing, "dry_run" => true } if dry?

        write_atomic(path, "#{content.join("\n")}\n")
        mark_need_reboot
        { "changed" => true, "added" => missing }
      end

      # ---- users, directories ----------------------------------------------------------------

      def ensure_user_and_dirs
        ensure_system_user(AUDIO_USER, "Shairport Sync", groups: "audio")
        ensure_system_user(UI_USER, "AirPlay OS web UI")
        gid = begin
          Etc.getgrnam(UI_USER).gid
        rescue ArgumentError
          nil
        end
        [[AirPlayOS.path(:etc), 0o755, false], [AirPlayOS.path(:state), 0o750, true], [AirPlayOS.path(:log), 0o755, false]].each do |dir, mode, group_owned|
          next if dry?

          FileUtils.mkdir_p(dir)
          File.chmod(mode, dir)
          File.chown(0, gid, dir) if group_owned && gid && root?
        end
        true
      end

      def ensure_system_user(name, comment, groups: nil)
        Etc.getpwnam(name)
        false
      rescue ArgumentError
        args = ["useradd", "--system", "--no-create-home", "--shell", "/usr/sbin/nologin", "--comment", comment]
        args += ["--groups", groups] if groups
        Run.run(*args, name, timeout: 60)
        true
      end

      # Rails needs a stable SECRET_KEY_BASE; generated once, readable by the airplay-os group only.
      def ensure_ui_secret
        path = AirPlayOS.path(:ui_secret)
        return false if File.exist?(path) && File.size(path) >= 64

        write_atomic(path, "#{SecureRandom.hex(64)}\n", mode: 0o640) unless dry?
        gid = begin
          Etc.getgrnam(UI_USER).gid
        rescue ArgumentError
          nil
        end
        File.chown(0, gid, path) if gid && root? && !dry?
        true
      end

      # ---- avahi: IPv4 only ------------------------------------------------------------------

      # Clients must never learn an AAAA record for the player (IPv6 stays firewalled).
      def ensure_avahi_ipv4(path: AirPlayOS.path(:avahi_conf), restart: true)
        return { "changed" => false, "skipped" => "no avahi-daemon.conf" } unless File.exist?(path)

        want = { "server" => { "use-ipv6" => "no" },
                 "publish" => { "publish-aaaa-on-ipv4" => "no", "publish-workstation" => "no" } }
        lines = File.read(path).lines.map(&:chomp)
        section = ""
        header_index = {}
        seen = Hash.new { |h, k| h[k] = {} }
        changed = false
        lines.each_with_index do |l, i|
          if (m = l.match(/\A\s*\[(\w[\w-]*)\]/))
            section = m[1]
            header_index[section] = i
            next
          end
          next unless want[section]

          want[section].each do |key, val|
            next unless l.match?(/\A\s*#?\s*#{Regexp.escape(key)}\s*=/)

            seen[section][key] = true
            line = "#{key}=#{val}"
            next if l == line

            lines[i] = line
            changed = true
          end
        end
        want.sort.each do |sec, keys|
          keys.sort.each do |key, val|
            next if seen[sec][key]

            line = "#{key}=#{val}"
            if (idx = header_index[sec])
              lines.insert(idx + 1, line)
              header_index.each { |s, i| header_index[s] = i + 1 if i > idx }
            else
              lines.push("", "[#{sec}]", line)
              header_index[sec] = lines.size - 2
            end
            changed = true
          end
        end
        return { "changed" => false } unless changed
        return { "changed" => true, "dry_run" => true } if dry?

        write_atomic(path, "#{lines.join("\n")}\n")
        if restart && Run.try_run("systemctl", "is-active", "avahi-daemon", quiet: true, read_only: true).status.zero?
          Run.run("systemctl", "restart", "avahi-daemon", timeout: 60)
        end
        { "changed" => true }
      end

      # ---- sshd: key-only access, validated before reload ----------------------------------------

      # The flake ships /etc/ssh/sshd_config.d/10-airplay-os.conf; this validates the merged config and
      # reloads sshd so the hardening is live without a reboot. Never reloads an invalid config.
      def ensure_sshd
        Run.run("sshd", "-t", timeout: 30)
        Run.run("systemctl", "reload-or-restart", "ssh", timeout: 60)
        true
      end

      # ---- hostname ----------------------------------------------------------------------------

      def ensure_pretty_hostname(pretty: AirPlayOS.device["pretty_name"])
        cur = Run.try_run("hostnamectl", "hostname", "--pretty", quiet: true, read_only: true)
        have = cur.status.zero? ? cur.out.strip : ""
        return false if have == pretty

        Run.run("hostnamectl", "set-hostname", "--pretty", pretty, timeout: 30)
        true
      end

      # ---- remove HiFiBerry OS leftovers -------------------------------------------------------

      def minimize
        summary = { "purged" => [], "removed_sources" => 0, "residue" => [], "linger_disabled" => false }
        %w[bluetooth hciuart].each { |svc| Run.try_run("systemctl", "disable", "--now", svc, timeout: 60) }

        q = Run.try_run("dpkg-query", "-W", "-f", '${Package}\t${db:Status-Status}\n', *LEFTOVER_PATTERNS, quiet: true, read_only: true)
        purge = q.out.lines.filter_map { |l| pkg, st = l.chomp.split("\t"); pkg if st == "installed" }
        unless purge.empty?
          Log.info("purging leftovers: #{purge.join(' ')}")
          Run.run("apt-get", "-y", "purge", *purge, timeout: 1800, env: { "DEBIAN_FRONTEND" => "noninteractive" })
          summary["purged"] = purge
        end
        [AirPlayOS.path(:hifiberry_list), AirPlayOS.path(:hifiberry_key)].each do |f|
          next unless File.exist?(f)

          Log.info("removing #{f}")
          File.unlink(f) unless dry?
          summary["removed_sources"] += 1
        end
        Run.run("apt-get", "update", timeout: 600, env: { "DEBIAN_FRONTEND" => "noninteractive" }) if summary["removed_sources"].positive?
        Run.run("apt-get", "-y", "autoremove", "--purge", timeout: 1800, env: { "DEBIAN_FRONTEND" => "noninteractive" })

        linger = Run.try_run("loginctl", "show-user", "pi", "-p", "Linger", "--value", quiet: true, read_only: true)
        if linger.status.zero? && linger.out.include?("yes")
          Run.run("loginctl", "disable-linger", "pi", timeout: 30)
          summary["linger_disabled"] = true
        end

        home = AirPlayOS.path(:pi_home)
        residue = [AirPlayOS.path(:hifiberry_user),
                   "#{home}/.config/systemd/user/default.target.wants/shairport.service",
                   "#{home}/.config/systemd/user/mpris-proxy.service",
                   *%w[.shairport .raat .squeezelite .state etc].map { |d| "#{home}/#{d}" }]
        residue.each do |p|
          next unless File.exist?(p) || File.symlink?(p)

          Log.info("removing residue #{p}")
          summary["residue"] << p
          next if dry?

          File.directory?(p) && !File.symlink?(p) ? FileUtils.rm_rf(p) : File.unlink(p)
        end
        summary
      end

      # ---- clean reboot: re-run cloud-init from scratch on the next boot -----------------------

      def clean_reboot(reset_settings: false, no_reboot: false)
        raise AirPlayOS::Error, "clean-reboot must run as root" unless root? || AirPlayOS::Run.runner || dry?

        if reset_settings && File.exist?(AirPlayOS.path(:settings))
          Log.info("resetting user settings to defaults")
          File.unlink(AirPlayOS.path(:settings)) unless dry?
        end
        Log.info("cloud-init clean --logs; rebooting to re-provision")
        Run.run("cloud-init", "clean", "--logs", timeout: 120)
        Run.run("sync", timeout: 60)
        Run.run("systemctl", "reboot", timeout: 60) unless no_reboot
        true
      end

      private

      def write_atomic(path, text, mode: 0o644)
        tmp = Tempfile.create([".#{File.basename(path)}.", ".tmp"], File.dirname(path))
        begin
          tmp.write(text)
          tmp.flush
          tmp.fsync
          tmp.close
          File.chmod(mode, tmp.path)
          File.rename(tmp.path, path)
        rescue StandardError
          File.unlink(tmp.path) if File.exist?(tmp.path)
          raise
        end
      end
    end
  end
end
