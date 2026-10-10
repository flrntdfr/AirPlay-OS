# frozen_string_literal: true

module AirPlayOS
  # Runtime provisioning, run as root after the Nix flake has been activated by system-manager
  # (first boot via cloud-init, Clean reboot, or `airplay-os provision` by hand). Everything the
  # flake cannot express lives here; each step is idempotent; the first failure stops the run.
  module Provision
    UNITS = %w[
      airplay-os-firewall.service nqptp.service shairport-sync.service airplay-os-metadata.service airplay-os-log.service
      airplay-os-control.socket airplay-os-ui.service airplay-os-wifi-fallback.timer avahi-daemon.service
    ].freeze

    class << self
      def steps
        [
          ["config_txt", -> { System.ensure_config_txt }],
          ["system", lambda {
            System.ensure_user_and_dirs
            System.ensure_ui_secret
            System.ensure_pretty_hostname
            System.ensure_avahi_ipv4
            Run.run("systemctl", "daemon-reload", timeout: 60)
            true
          }],
          ["ssh", -> { System.ensure_sshd }],
          ["settings", -> { Settings.apply }],
          ["services", lambda {
            UNITS.each do |u|
              r = Run.try_run("systemctl", "enable", "--now", u, timeout: 60)
              Log.warning("could not enable #{u}: #{r.err.strip}") unless r.status.zero?
            end
            true
          }],
          ["minimize", -> { System.minimize }],
          ["wifi", lambda {
            next "no Wi‑Fi on this device" unless AirPlayOS.device["wifi"]

            begin
              Wifi.ensure["action"]
            rescue StandardError => e
              Log.warning("wifi check failed: #{e.message}")
              "failed"
            end
          }],
          ["reboot", lambda {
            next "not needed" unless System.needs_reboot?

            File.unlink(AirPlayOS.path(:need_reboot)) unless Run.dry_run
            Log.info("config.txt changed: rebooting to apply the device tree")
            Run.run("systemctl", "reboot", timeout: 60)
            "rebooting"
          }]
        ]
      end

      # Run all steps (optionally skipping some by name). Returns { step => result } or raises.
      def run_all(skip: [])
        done = {}
        t0 = Time.now
        Log.info("airplay-os provision #{AirPlayOS::VERSION} starting#{Run.dry_run ? ' (dry-run)' : ''}")
        steps.each do |name, code|
          if skip.include?(name)
            Log.info("[#{name}] skipped")
            done[name] = "skipped"
            next
          end
          Log.info("[#{name}] start")
          t = Time.now
          begin
            r = code.call
          rescue StandardError => e
            Log.error("[#{name}] FAILED: #{e.message}")
            raise AirPlayOS::Error, "provision step '#{name}' failed: #{e.message}"
          end
          done[name] = r.is_a?(String) ? r : "ok"
          Log.info(format("[%s] done (%ds)", name, Time.now - t))
        end
        Log.info(format("airplay-os provision finished in %ds", Time.now - t0))
        done
      end
    end
  end
end
