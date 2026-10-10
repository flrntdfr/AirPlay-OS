# system-manager module: everything above the Raspberry Pi OS kernel that makes the box an
# AirPlay 2 speaker (the firewall lives in firewall.nix). Runtime-mutable state stays outside Nix:
#   /etc/shairport-sync.conf  rendered by `airplay-os settings apply` (defaults ⊕ user settings)
#   NetworkManager profiles   nmcli (onboarding); /boot/firmware/* (apt-owned firmware, cloud-init seed)
#
# Privilege model: the web UI runs as the unprivileged system user "airplay-os" (nologin, no sudo).
# Root work happens only in the socket-activated control handler, which runs allow-listed actions
# (built-ins + /etc/airplay-os/actions.json).
{
  config,
  lib,
  pkgs,
  airplay-os,
  ...
}:
let
  tools = airplay-os.airplay-os-tools;
  ui = airplay-os.airplay-os-ui;
  shairport = airplay-os.shairport-sync-airplay2;
  nqptp = airplay-os.nqptp;
  device = airplay-os.device; # docs/devices/<id>.json — hostname, HAT, radios, defaults
  # system-manager gives units a Nix-only PATH. The Ruby tools drive the Debian side of the box
  # (nmcli, systemctl, journalctl, apt-get, cloud-init, hostnamectl…), which lives in /usr/{bin,sbin}.
  debianPath = [ "/usr" ];
  # Rails needs a stable SECRET_KEY_BASE. Created on first start (as root, before dropping to the
  # airplay-os user) so the unit never depends on `airplay-os provision` having run first.
  ensureUiSecret = pkgs.writeShellScript "airplay-os-ui-secret" ''
    set -eu
    f=/var/lib/airplay-os/ui-secret
    [ -s "$f" ] && exit 0
    umask 077
    install -d -m 0750 -o root -g airplay-os /var/lib/airplay-os
    od -An -tx1 -N 64 /dev/urandom | tr -d ' \n' > "$f.tmp"
    echo >> "$f.tmp"
    chown root:airplay-os "$f.tmp"
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
      airplay-os.systemManager
    ];

    # The flake source that produced this system travels inside the closure; /opt/airplay-os points
    # at it so Redeploy / Clean reboot re-evaluate exactly this source on the device — no rsync.
    systemd.tmpfiles.rules = [
      "L+ /opt/airplay-os - - - - ${airplay-os.flakeSource}"
    ];

    environment.etc = {
      # the device definition and its shairport-sync defaults, straight from docs/devices/<id>.json
      "airplay-os/device.json".text = builtins.toJSON device;
      "airplay-os/defaults.json".text = builtins.toJSON device.defaults;
      "airplay-os/actions.json".source = ../../etc/airplay-os/actions.json;
      "airplay-os/flake-version".text = "${airplay-os.version}\n";
      # SSH: keys only, no passwords, no root, one user. Sorts before cloud-init's 50-cloud-init.conf,
      # and sshd keeps the first value it sees, so these win. Validated + reloaded by `airplay-os provision`.
      "ssh/sshd_config.d/10-airplay-os.conf".text = ''
        # AirPlay OS (Nix flake): key-based authentication only
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
    }
    // lib.optionalAttrs device.wifi {
      # Onboarding hotspot: NetworkManager's shared-mode dnsmasq answers every name with the
      # hotspot address so the phone's captive-portal sheet lands on the setup page.
      "NetworkManager/dnsmasq-shared.d/airplay-os-captive.conf".text = ''
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
      description = "Shairport Sync — AirPlay 2 audio receiver (AirPlay OS)";
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
        # crash-loop protection only: explicit restarts count too, and the Settings pane restarts
        # the receiver after every saved keystroke burst (5 per 5 min tripped it on 2026-10-09)
        StartLimitIntervalSec = 60;
        StartLimitBurst = 20;
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

    systemd.sockets.airplay-os-control = {
      description = "AirPlay OS control socket (web UI → allow-listed root actions)";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "/run/airplay-os-control.sock";
        SocketUser = "root";
        SocketGroup = "airplay-os";
        SocketMode = "0660";
        Accept = true;
        MaxConnections = 8;
        RemoveOnStop = true;
      };
    };

    systemd.services."airplay-os-control@" = {
      description = "AirPlay OS control handler (%i)";
      path = debianPath;
      # a template: every connection spawns a fresh instance from the new unit file, and a bare
      # template cannot be restarted (activation would log "error reloading")
      restartIfChanged = false;
      stopIfChanged = false;
      # CollectMode is a [Unit] setting: in [Service] systemd ignored it and every instance that
      # exited non-zero lingered as "failed" (and tripped verify.sh's "no failed units")
      unitConfig.CollectMode = "inactive-or-failed";
      serviceConfig = {
        ExecStart = "${tools}/bin/airplay-os control handle";
        StandardInput = "socket";
        StandardOutput = "socket";
        StandardError = "journal";
        User = "root";
        TimeoutStartSec = "3600";
      };
    };

    # ---- metadata + web UI (unprivileged) -----------------------------------------------------

    systemd.services.airplay-os-metadata = {
      description = "AirPlay OS metadata daemon (shairport-sync pipe → now-playing state)";
      wantedBy = [ "multi-user.target" ];
      after = [ "shairport-sync.service" ];
      wants = [ "shairport-sync.service" ];
      serviceConfig = {
        ExecStart = "${tools}/bin/airplay-os metadata daemon";
        User = "airplay-os";
        Group = "airplay-os";
        RuntimeDirectory = "airplay-os";
        RuntimeDirectoryMode = "0755";
        Restart = "always";
        RestartSec = "2s";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    systemd.services.airplay-os-ui = {
      description = "AirPlay OS web UI (Rails)";
      path = debianPath; # avahi-browse: play/pause finds the sender's DACP service via mDNS
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "airplay-os-metadata.service"
        "airplay-os-control.socket"
      ];
      wants = [ "airplay-os-control.socket" ];
      serviceConfig = {
        User = "airplay-os";
        Group = "airplay-os";
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
        NoNewPrivileges = true; # no sudo/polkit anywhere in the UI: nothing to escalate to
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        # "+" = runs as root outside the sandbox; creates the secret if missing (see ensureUiSecret)
        ExecStartPre = "+${ensureUiSecret}";
        LoadCredential = "secret_key_base:/var/lib/airplay-os/ui-secret";
        Environment = [
          "RAILS_ENV=production"
          "RAILS_LOG_TO_STDOUT=1"
          "RAILS_LOG_LEVEL=warn" # the live log polls every 2 s; access lines would drown it
          "PORT=80"
          "AIRPLAY_OS_RUN_DIR=/run/airplay-os"
          "AIRPLAY_OS_CONTROL_SOCKET=/run/airplay-os-control.sock"
          "AIRPLAY_OS_ACTIONS_FILE=/etc/airplay-os/actions.json"
          "AIRPLAY_OS_RELEASE_FILE=/etc/airplay-os/release"
        ];
        Restart = "on-failure";
        RestartSec = "3s";
      };
      # Puma reads SECRET_KEY_BASE from the systemd credential, hence a script instead of ExecStart.
      script = ''
        export SECRET_KEY_BASE="$(cat "$CREDENTIALS_DIRECTORY/secret_key_base")"
        exec ${ui}/bin/airplay-os-ui
      '';
    };

    # ---- the live log behind the UI ----------------------------------------------------------

    systemd.services.airplay-os-log = {
      description = "AirPlay OS live log (journal → /var/log/airplay-os.log, the UI backdrop)";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-journald.service" ];
      path = debianPath;
      serviceConfig = {
        ExecStart = "${tools}/bin/airplay-os log aggregate";
        User = "root"; # journal access; writes a world-readable, size-capped file
        Restart = "always";
        RestartSec = "3s";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    # ---- Wi-Fi fallback timer (Wi‑Fi devices only: an Ethernet-only box keeps its radio off) ----

    systemd.services.airplay-os-wifi-fallback = lib.mkIf device.wifi {
      description = "AirPlay OS Wi-Fi check / onboarding hotspot";
      path = debianPath;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${tools}/bin/airplay-os wifi ensure";
      };
    };
    systemd.timers.airplay-os-wifi-fallback = lib.mkIf device.wifi {
      description = "Periodic AirPlay OS Wi-Fi check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "90s";
        OnUnitActiveSec = "3min";
        Unit = "airplay-os-wifi-fallback.service";
      };
    };

    # ---- health line every quarter hour, on the clock (→ journal → live log, shown green) ------
    systemd.services.airplay-os-health = {
      description = "AirPlay OS health line (temperature, cpu, memory)";
      serviceConfig = {
        Type = "oneshot";
        User = "airplay-os";
        ExecStart = "${tools}/bin/airplay-os health";
        SuccessExitStatus = "0 1"; # 1 = degraded, still just a log line
      };
    };
    systemd.timers.airplay-os-health = {
      description = "AirPlay OS health line at :00 :15 :30 :45";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* *:00/15:00";
        AccuracySec = "1s"; # on the quarter hour, not somewhere in the following minute
        Unit = "airplay-os-health.service";
      };
    };

    # ---- shairport-sync update check, daily (and on demand from the UI) ----------------------
    systemd.services.airplay-os-updates = {
      description = "AirPlay OS: is shairport-sync the latest release?";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "airplay-os";
        ExecStart = "${tools}/bin/airplay-os updates check";
        RuntimeDirectory = "airplay-os";
        RuntimeDirectoryPreserve = true; # shared with the metadata daemon: never wipe it
        RuntimeDirectoryMode = "0755";
      };
    };
    systemd.timers.airplay-os-updates = {
      description = "Daily shairport-sync update check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitActiveSec = "1d";
        Unit = "airplay-os-updates.service";
      };
    };
  };
}
