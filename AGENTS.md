# AGENTS.md

Guidance for an AI assistant operating this repo. See [`README.md`](./README.md) for the full
framing — this repo is **Infrastructure as Context** for two Raspberry Pi audio appliances, not
deployment automation.

## Start here

1. Identify which device the task concerns and **read its doc first** — it is the source of truth:
   - [`Ampberry.md`](./Ampberry.md) — Pi 3B + DAC+/**Amp2**, powered speaker, Wi‑Fi `192.168.178.221`.
     **Nix-managed AirPlay 2 appliance** since 2026-10-08: Raspberry Pi OS Lite + the
     [`ampberry-v2/`](./ampberry-v2/README.md) flake (system-manager). Not hbos anymore.
   - [`HifiBerry.md`](./HifiBerry.md) — Pi 4B + **DAC+** line-out, Ethernet-only `192.168.178.244`,
     HiFiBerry OS NG (hbosng).
2. Connect over SSH as `pi` (key-based only, passwordless sudo on both):
   `ssh pi@ampberry.local` · `ssh pi@HifiBerry.local`
3. Follow that device's **Agent guidelines** section (Do / Ask-first / Never).

## Operating rules

- **Live appliances.** People listen to these. Prefer config edits + restarting the specific
  service over rebooting.
- **Two different stacks.**
  - *HifiBerry (hbosng):* `systemctl --user` for PipeWire, WirePlumber, filter-chain, MPD and
    players; `sudo systemctl` for `audiocontrol`, `nginx`, `config-server`, `sigmatcpserver`;
    config under `/etc/` or `/home/pi/.state/`.
  - *Ampberry (Nix):* change the stack **in the flake** (`ampberry-v2/`), test locally
    (`tools/build-image.sh`), deploy with `system-manager … --target-host`; runtime-only things go
    through the `ampberry` tools (settings, Wi‑Fi, provisioning). All system units, no user units.
    **Never rsync to the device; never give the `ampberry` user privilege; no volume control in the UI.**
- **Verify audio for real** — `aplay -l`, the player's status/UI, a listen-test — not just config
  syntax. HifiBerry: `wpctl status`, `pw-link -l`, gain chain PipeWire → Speaker EQ → ALSA
  `Digital`/`Analogue` (unity). Ampberry: `systemctl status shairport-sync nqptp`, `tools/verify.sh`,
  the `volume_max_db` ceiling (−6 dB) — the amp shuts down above it.
- **Updates are split on purpose.** `unattended-upgrades` handles Debian **security** only
  (auto-reboot 04:00) on both. HiFiBerry-stack (HifiBerry) and kernel/firmware upgrades are a
  **manual, listen-tested** `sudo apt upgrade` — never automate them. Ampberry's appliance stack
  changes only through the flake (pinned `flake.lock`).
- **arm64 only.** Never assume x86 binaries (Ampberry builds happen on the nix-darwin
  `linux-builder` or in the pi-gen chroot).
- **Never** commit or log secrets (MPD/Spotify/Last.fm keys, SSH keys, Wi‑Fi PSK, hotspot PSK, the
  `pi` password hash, Rails secret — Ampberry's live in `ampberry-v2/secrets.env`/`build/`, both
  gitignored), and don't re-enable HifiBerry's Wi‑Fi/Bluetooth radios without being asked —
  Ethernet-only is intentional.

## Keep context in sync

When you change a device's state (config, services, policy, volume chain), **update that device's
`.md` in the same session**, with a dated note for non-obvious decisions. The docs must never drift
from the running machines — that is the whole point of this repo.

## Log operations

Any action that changes a device's running state — package upgrades, service restarts tied to a
change, config edits, fixes — gets a dated entry in [`OPERATIONS.md`](./OPERATIONS.md), added in
the same session the action was taken. Entry should cover: device, what was run, what changed
(versions before → after for upgrades), verification performed, and any issues hit. Keep it
proportional — summarize bulk/routine package bumps (e.g. "42 Debian security packages"), but call
out anything notable in full (HiFiBerry-stack version jumps, kernel/firmware changes, anything that
needed a non-default fix). This is a log, not a rewrite of history — append, don't edit past
entries except to fix errors.

## Ask first

Rebooting / Clean reboot (interrupts playback/SSH), `apt upgrade` / package removal on the audio
stack, `/boot/firmware/config.txt` overlay changes, disabling players that may be in active use,
and (Ampberry) changing the firewall posture, the LAN CIDR, or `volume_max_db` upward.
