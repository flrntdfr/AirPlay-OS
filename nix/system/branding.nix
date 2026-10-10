# Branding that lives in the flake (the pi-gen stage writes the image-level counterpart), from
# the device definition (devices/<id>.json). Only files no Debian package owns, so
# unattended-upgrades never sees a modified conffile.
{ airplay-os, ... }:
let
  d = airplay-os.device;
  pretty = "${d.pretty_name} — ${d.description}";
in
{
  config = {
    environment.etc = {
      "airplay-os/release".text = ''
        NAME="${d.pretty_name}"
        PRETTY_NAME="${pretty}"
        DEVICE="${d.id}"
        FLAKE_VERSION="${airplay-os.version}"
        BUILD="${airplay-os.build}"
        MANAGED_BY="Nix flake via system-manager"
      '';
      "issue.d/airplay-os.issue".text = ''
        ${pretty} · web ui: http://${d.hostname}.local/
      '';
      "update-motd.d/10-airplay-os" = {
        mode = "0755";
        text = ''
          #!/bin/sh
          # MOTD — minimal on purpose.
          . /etc/airplay-os/release 2>/dev/null
          ip4=$(ip -4 -o addr show dev ${d.primary_interface} 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
          printf '\n  %s\n' "''${PRETTY_NAME:-${d.pretty_name}}"
          printf '  web ui   http://${d.hostname}.local/%s\n' "''${ip4:+   ($ip4)}"
          printf '  manage   sudo airplay-os help · build %s (%s)\n\n' "''${BUILD:-dev}" "''${FLAKE_VERSION:-}"
        '';
      };
    };
  };
}
