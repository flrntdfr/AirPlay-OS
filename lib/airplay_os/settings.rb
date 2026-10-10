# frozen_string_literal: true

require "tempfile"

module AirPlayOS
  # Renders /etc/shairport-sync.conf from the effective settings (AirPlay 2 only) and restarts the
  # receiver. nqptp is always on; the firewall is static (nix/system/firewall.nix).
  module Settings
    class << self
      # Pure: settings hash → libconfig text.
      def render_conf(settings)
        s = settings.transform_keys(&:to_s)
        known = s.select { |k, _| Config::SCHEMA.key?(k) }
        problems = Config.validate_settings(known)
        raise Config::InvalidSettings, problems unless problems.empty?

        password = s["password"].to_s.empty? ? "" : "  password = #{q(s['password'])};\n"
        <<~CONF
          // Managed by airplay-os (AirPlayOS::Settings). Change settings in the web UI or with
          //   echo '{"settings":{"name":"..."}}' | sudo airplay-os settings apply
          // Manual edits are overwritten on the next apply / clean reboot.
          general = {
            name = #{q(s.fetch('name', 'Ampberry'))};
            service_type = "airplay2";
          #{password}  interpolation = #{q(s.fetch('interpolation', 'auto'))};
            output_backend = "alsa";
            mdns_backend = "avahi";
            volume_range_db = #{Integer(s.fetch('volume_range_db', 60).to_f)};
            volume_max_db = #{db(s.fetch('volume_max_db', -6))};
            playback_mode = "stereo";
          };

          sessioncontrol = {
            allow_session_interruption = "yes";
            session_timeout = 60;
          };

          alsa = {
            output_device = "hw:0";
            mixer_control_name = "Digital";
            mixer_device = "hw:0";
            output_format = #{q(s.fetch('output_format', 'S32_LE'))};
            output_rate = "auto";
          };

          metadata = {
            enabled = "yes";
            include_cover_art = "yes";
            pipe_name = "#{AirPlayOS.path(:metadata_pipe)}";
            pipe_timeout = 5000;
          };

          diagnostics = {
            log_verbosity = 0;
          };
        CONF
      end

      # Write the rendered config atomically (0644).
      def write_conf(text)
        path = AirPlayOS.path(:shairport_conf)
        tmp = Tempfile.create([".shairport-sync.conf.", ".tmp"], File.dirname(path))
        begin
          tmp.write(text)
          tmp.flush
          tmp.fsync
          tmp.close
          File.chmod(0o644, tmp.path)
          File.rename(tmp.path, path)
        rescue StandardError
          File.unlink(tmp.path) if File.exist?(tmp.path)
          raise
        end
        path
      end

      # Apply: optionally persist new settings, render, write, restart. Returns the effective settings.
      def apply(settings: nil)
        Config.save_settings(settings) if settings
        eff = Config.effective_settings
        write_conf(render_conf(eff))

        Run.run("systemctl", "enable", "--now", "nqptp", timeout: 60)
        Run.run("systemctl", "enable", "shairport-sync", timeout: 60)
        # a receiver that tripped its start limit (many quick saves) must come back with the next save
        Run.try_run("systemctl", "reset-failed", "shairport-sync", quiet: true)
        Run.run("systemctl", "restart", "shairport-sync", timeout: 90)
        eff
      end

      private

      # libconfig string escaping
      def q(value)
        %("#{value.to_s.gsub(/[\\"]/) { "\\#{$&}" }}")
      end

      # shairport-sync insists on a decimal point in dB values
      def db(value)
        f = Float(value)
        f == f.floor ? format("%.1f", f) : f.to_s
      end
    end
  end
end
