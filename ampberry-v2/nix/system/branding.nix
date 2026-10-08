# Branding that lives in the flake (the pi-gen stage writes the image-level counterpart).
# Only files no Debian package owns, so unattended-upgrades never sees a modified conffile.
{ ampberry, ... }:
{
  config = {
    environment.etc = {
      "ampberry/release".text = ''
        NAME="Ampberry"
        PRETTY_NAME="Ampberry — AirPlay 2 speaker"
        FLAKE_VERSION="${ampberry.version}"
        BUILD="${ampberry.build}"
        MANAGED_BY="Nix flake via system-manager"
      '';
      "issue.d/ampberry.issue".text = ''
        Ampberry — AirPlay 2 speaker · web ui: http://ampberry.local/
      '';
      "update-motd.d/10-ampberry" = {
        mode = "0755";
        text = ''
          #!/bin/sh
          # Ampberry MOTD — minimal on purpose.
          . /etc/ampberry/release 2>/dev/null
          ip4=$(ip -4 -o addr show dev wlan0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
          printf '\n  %s\n' "''${PRETTY_NAME:-Ampberry}"
          printf '  web ui   http://ampberry.local/%s\n' "''${ip4:+   ($ip4)}"
          printf '  manage   sudo ampberry help · build %s (%s)\n\n' "''${BUILD:-dev}" "''${FLAKE_VERSION:-}"
        '';
      };
    };
  };
}
