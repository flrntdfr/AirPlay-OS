# system-manager module: everything above the Raspberry Pi OS kernel that makes the box an
# AirPlay 2 speaker (the firewall lives in firewall.nix). Runtime-mutable state stays outside Nix:
#   /etc/shairport-sync.conf  rendered by `ampberry settings apply` (defaults ⊕ user settings)
#   NetworkManager profiles   nmcli (onboarding); /boot/firmware/* (apt-owned firmware, cloud-init seed)
#
# Privilege model: the web UI runs as the unprivileged system user "ampberry" (nologin, no sudo).
# Root work happens only in the socket-activated control handler, which runs allow-listed actions
# (built-ins + /etc/ampberry/actions.json).
{
  config,
  lib,
  pkgs,
  ampberry,
  ...
}:
let
  tools = ampberry.ampberry-tools;
  ui = ampberry.ampberry-ui;
  shairport = ampberry.shairport-sync-airplay2;
  nqptp = ampberry.nqptp;
  # system-manager gives units a Nix-only PATH. The Ruby tools drive the Debian side of the box
  # (nmcli, systemctl, journalctl, apt-get, cloud-init, hostnamectl…), which lives in /usr/{bin,sbin}.
  debianPath = [ "/usr" ];
  # Rails needs a stable SECRET_KEY_BASE. Created on first start (as root, before dropping to the
  # ampberry user) so the unit never depends on `ampberry provision` having run first.
  ensureUiSecret = pkgs.writeShellScript "ampberry-ui-secret" ''
    set -eu
    f=/var/lib/ampberry/ui-secret
    [ -s "$f" ] && exit 0
    umask 077
    install -d -m 0750 -o root -g ampberry /var/lib/ampberry
    od -An -tx1 -N 64 /dev/urandom | tr -d ' \n' > "$f.tmp"
    echo >> "$f.tmp"
    chown root:ampberry "$f.tmp"
    chmod 0640 "$f.tmp"
    mv "$f.tmp" "$f"
  '';
in
{
  config = {
    nixpkgs.hostPlatform = "aarch64-linux";

    environment.systemPackages = [
      tools
      shairport
      nqptp
      # the CLI itself, so Redeploy / Clean reboot never build it on the Pi
      ampberry.systemManager
    ];

    # The flake source that produced this system travels inside the closure; /opt/ampberry points
    # at it so Redeploy / Clean reboot re-evaluate exactly this source on the device — no rsync.
    systemd.tmpfiles.rules = [
      "L+ /opt/ampberry - - - - ${ampberry.flakeSource}"
    ];

    environment.etc = {
      "ampberry/defaults.json".source = ../../etc/ampberry/defaults.json;
      "ampberry/actions.json".source = ../../etc/ampberry/actions.json;
      "ampberry/flake-version".text = "${ampberry.version}\n";
      # SSH: keys only, no passwords, no root, one user. Sorts before cloud-init's 50-cloud-init.conf,
      # and sshd keeps the first value it sees, so these win. Validated + reloaded by `ampberry provision`.
      "ssh/sshd_config.d/10-ampberry.conf".text = ''
        # Ampberry (Nix flake): key-based authentication only
        PubkeyAuthentication yes
        AuthenticationMethods publickey
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        ChallengeResponseAuthentication no
        PermitEmptyPasswords no
        PermitRootLogin no
        AllowUsers pi
        MaxAuthTries 3
        LoginGraceTime 30
        X11Forwarding no
        ClientAliveInterval 300
        ClientAliveCountMax 2
      '';
      # Onboarding hotspot: NetworkManager's shared-mode dnsmasq answers every name with the
      # hotspot address so the phone's captive-portal sheet lands on the setup page.
      "NetworkManager/dnsmasq-shared.d/ampberry-captive.conf".text = ''
        address=/#/10.42.0.1
      '';
    };

    # ---- AirPlay 2 ---------------------------------------------------------------------------

    systemd.services.nqptp = {
      description = "NQPTP — Not Quite PTP (AirPlay 2 timing)";
      documentation = [ "https://github.com/mikebrady/nqptp" ];
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network.target"
        "network-online.target"
      ];
      before = [ "shairport-sync.service" ];
      serviceConfig = {
        ExecStart = "${nqptp}/bin/nqptp";
        DynamicUser = true;
        LimitRTPRIO = 6;
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    systemd.services.shairport-sync = {
      description = "Shairport Sync — AirPlay 2 audio receiver (Ampberry)";
      documentation = [ "https://github.com/mikebrady/shairport-sync" ];
      wantedBy = [ "multi-user.target" ];
      wants = [
        "network-online.target"
        "nqptp.service"
        "avahi-daemon.service"
      ];
      after = [
        "sound.target"
        "network.target"
        "network-online.target"
        "nqptp.service"
        "avahi-daemon.service"
      ];
      unitConfig = {
        ConditionPathExists = "/etc/shairport-sync.conf";
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
      };
      serviceConfig = {
        ExecStart = "${shairport}/bin/shairport-sync -c /etc/shairport-sync.conf";
        User = "shairport-sync";
        Group = "shairport-sync";
        SupplementaryGroups = [ "audio" ];
        # metadata pipe lives here (world-readable dir, pipe created by shairport-sync)
        RuntimeDirectory = "shairport-sync";
        RuntimeDirectoryMode = "0755";
        LimitRTPRIO = 5;
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    # ---- control API (root side) ---------------------------------------------------------------

    systemd.sockets.ampberry-control = {
      description = "Ampberry control socket (web UI → allow-listed root actions)";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "/run/ampberry-control.sock";
        SocketUser = "root";
        SocketGroup = "ampberry";
        SocketMode = "0660";
        Accept = true;
        MaxConnections = 8;
        RemoveOnStop = true;
      };
    };

    systemd.services."ampberry-control@" = {
      description = "Ampberry control handler (%i)";
      path = debianPath;
      # a template: every connection spawns a fresh instance from the new unit file, and a bare
      # template cannot be restarted (activation would log "error reloading")
      restartIfChanged = false;
      stopIfChanged = false;
      serviceConfig = {
        ExecStart = "${tools}/bin/ampberry control handle";
        StandardInput = "socket";
        StandardOutput = "socket";
        StandardError = "journal";
        User = "root";
        TimeoutStartSec = "3600";
        CollectMode = "inactive-or-failed";
      };
    };

    # ---- metadata + web UI (unprivileged) -----------------------------------------------------

    systemd.services.ampberry-metadata = {
      description = "Ampberry metadata daemon (shairport-sync pipe → now-playing state)";
      wantedBy = [ "multi-user.target" ];
      after = [ "shairport-sync.service" ];
      wants = [ "shairport-sync.service" ];
      serviceConfig = {
        ExecStart = "${tools}/bin/ampberry metadata daemon";
        User = "ampberry";
        Group = "ampberry";
        RuntimeDirectory = "ampberry";
        RuntimeDirectoryMode = "0755";
        Restart = "always";
        RestartSec = "2s";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    systemd.services.ampberry-ui = {
      description = "Ampberry web UI (Rails)";
      path = debianPath; # avahi-browse: play/pause finds the sender's DACP service via mDNS
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "ampberry-metadata.service"
        "ampberry-control.socket"
      ];
      wants = [ "ampberry-control.socket" ];
      serviceConfig = {
        User = "ampberry";
        Group = "ampberry";
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
        NoNewPrivileges = true; # no sudo/polkit anywhere in the UI: nothing to escalate to
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        # "+" = runs as root outside the sandbox; creates the secret if missing (see ensureUiSecret)
        ExecStartPre = "+${ensureUiSecret}";
        LoadCredential = "secret_key_base:/var/lib/ampberry/ui-secret";
        Environment = [
          "RAILS_ENV=production"
          "RAILS_LOG_TO_STDOUT=1"
          "RAILS_LOG_LEVEL=warn" # the live log polls every 2 s; access lines would drown it
          "PORT=80"
          "AMPBERRY_RUN_DIR=/run/ampberry"
          "AMPBERRY_CONTROL_SOCKET=/run/ampberry-control.sock"
          "AMPBERRY_ACTIONS_FILE=/etc/ampberry/actions.json"
          "AMPBERRY_RELEASE_FILE=/etc/ampberry/release"
        ];
        Restart = "on-failure";
        RestartSec = "3s";
      };
      # Puma reads SECRET_KEY_BASE from the systemd credential, hence a script instead of ExecStart.
      script = ''
        export SECRET_KEY_BASE="$(cat "$CREDENTIALS_DIRECTORY/secret_key_base")"
        exec ${ui}/bin/ampberry-ui
      '';
    };

    # ---- the live log behind the UI ----------------------------------------------------------

    systemd.services.ampberry-log = {
      description = "Ampberry live log (journal → /var/log/ampberry.log, the UI backdrop)";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-journald.service" ];
      path = debianPath;
      serviceConfig = {
        ExecStart = "${tools}/bin/ampberry log aggregate";
        User = "root"; # journal access; writes a world-readable, size-capped file
        Restart = "always";
        RestartSec = "3s";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    # ---- Wi-Fi fallback timer ----------------------------------------------------------------

    systemd.services.ampberry-wifi-fallback = {
      description = "Ampberry Wi-Fi check / onboarding hotspot";
      path = debianPath;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${tools}/bin/ampberry wifi ensure";
      };
    };
    systemd.timers.ampberry-wifi-fallback = {
      description = "Periodic Ampberry Wi-Fi check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "90s";
        OnUnitActiveSec = "3min";
        Unit = "ampberry-wifi-fallback.service";
      };
    };
  };
}
