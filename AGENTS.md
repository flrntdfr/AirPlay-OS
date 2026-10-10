# AGENTS.md

Guidance for an AI assistant working in this repo. The repo **is the operating system** — AirPlay
OS, an AirPlay 2 receiver appliance for Raspberry Pis built on Raspberry Pi OS Lite with
everything above the kernel declared in the Nix flake at the root and applied with
[system-manager](https://github.com/numtide/system-manager). The devices it runs on are
**defined** in `devices/<id>.json` and **recorded** in `devices/<Id>.md` (what is installed, which
build, since when). `OPERATIONS.md` is the dated log of everything done to a device.

## Start here

1. Read [`README.md`](./README.md) (what the OS is) and [`docs/architecture.md`](./docs/architecture.md)
   (how it is put together: units, security model, UI, paths).
2. Identify the device: [`devices/Ampberry.md`](./devices/Ampberry.md) (Pi 3B + HiFiBerry Amp2,
   Wi‑Fi `192.168.178.221`, on AirPlay OS since 2026-10-08) or
   [`devices/HifiBerry.md`](./devices/HifiBerry.md) (Pi 4B + DAC+ line-out, Ethernet-only
   `192.168.178.244` — still HiFiBerry OS NG until its migration is run). Its `devices/<id>.json`
   is the single source for hostname, HAT overlay, radios, LAN and shairport-sync defaults; the
   flake ships it to the box as `/etc/ampberry/device.json`.
3. Connect as `pi` (SSH keys only, passwordless sudo): `ssh pi@ampberry.local` · `ssh pi@HifiBerry.local`.

## Operating rules

- **Live appliances.** People listen to these. Prefer a settings change or a service restart over
  a reboot; every settings save already restarts the receiver for a few seconds.
- **One way to change the stack:** edit the flake, run the tests
  (`nix shell nixpkgs#ruby_3_4 --command ruby -Ilib -Itest -e 'Dir["test/*_test.rb"].sort.each { |f| require File.expand_path(f) }'`),
  build the UI package (`nix build .#ampberry-ui` renders every page), then deploy:
  `nix run github:numtide/system-manager/release-26.05 -- switch --flake .#<id> --target-host pi@<host> --sudo`,
  then `DEVICE=<id> tools/verify.sh`. Deploy from a **clean checkout** (a detached worktree of the
  commit) — the build number is the commit count and a dirty tree deploys as `dev`. Runtime-only
  things (settings, Wi‑Fi, provisioning) go through the `ampberry` tools. All system units, no user units.
- **Never rsync to a device; never give the `ampberry` user privilege; no volume control in the UI**
  (`volume_max_db` is the ceiling — −6 dB on Ampberry, listen-tested: the Amp2 shuts down above it).
- **Verify audio for real** — `systemctl status shairport-sync nqptp`, `tools/verify.sh`, the live
  log on the home page, a listen-test — not just config syntax.
- **Updates are split on purpose.** `unattended-upgrades` handles Debian **security** only
  (auto-reboot 04:00). Kernel/firmware upgrades are a manual, listen-tested `sudo apt upgrade`.
  The appliance stack changes only through the flake (pinned `flake.lock`); the Settings pane's
  update badge can put a newer shairport-sync release on top until the next deploy.
- **arm64 only.** Builds happen on the nix-darwin `linux-builder` (or on the Pi for the on-device
  shairport-sync update). Never assume x86 binaries.
- **Never** commit or log secrets (Wi‑Fi PSK, hotspot PSK, SSH keys, the `pi` password hash, the
  Rails secret — they live in `secrets.env` / `build/`, both gitignored), and don't re-enable
  HifiBerry's Wi‑Fi/Bluetooth radios: `devices/hifiberry.json` says Ethernet-only on purpose.

## Keep context in sync

When a device's state changes (build deployed, settings, hardware), update **its `devices/<Id>.md`
record in the same session** — build number, flake revision, versions, date. The records must
never drift from the running machines. Architecture changes go to `docs/architecture.md`.

## Log operations

Any action that changes a device's running state — a deploy, package upgrades, service restarts
tied to a change, config edits, fixes — gets a dated entry in [`OPERATIONS.md`](./OPERATIONS.md),
added in the same session: device, what was run, what changed (versions before → after),
verification performed, issues hit. Proportional: summarize routine bumps, call out anything
notable in full. Append; don't rewrite past entries except to fix errors.

## Ask first

Rebooting / Clean reboot (interrupts playback and SSH), purging or upgrading packages on a device
that still runs HiFiBerry OS, `/boot/firmware/config.txt` overlay changes outside the flake, changing
the firewall posture or the LAN CIDR, raising `volume_max_db` on Ampberry, tagging a release
(`v35` is tagged when Florent has confirmed everything works), pushing to the remote.
