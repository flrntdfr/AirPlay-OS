# HiFiBerry — Infrastructure as Context

This repository is the **Infrastructure as Context** for two Raspberry Pi audio appliances:
**HifiBerry** runs [HiFiBerry OS Next Generation (hbosng)](https://github.com/hifiberry/hifiberry-os/tree/hbosng);
**Ampberry** is a Nix-managed AirPlay 2 speaker on Raspberry Pi OS Lite, whose flake lives here in
[`ampberry-v2/`](./ampberry-v2/README.md).

It is not deployment automation. It is a curated, human- and agent-readable description of
**what these machines are, how they're wired, and the decisions behind their current state** —
the context an AI assistant (or a future me) needs to operate them safely without re-discovering
everything from scratch each time.

## Devices

| Device | Doc | Board + HAT | Role | Network |
|--------|-----|-------------|------|---------|
| **Ampberry** | [`Ampberry.md`](./Ampberry.md) | Pi 3B + DAC+/**Amp2** | AirPlay 2 powered speaker (built-in amp → passive speakers) — Raspberry Pi OS Lite + Nix flake (`ampberry-v2/`) | Wi‑Fi `192.168.178.221` |
| **HifiBerry** | [`HifiBerry.md`](./HifiBerry.md) | Pi 4B + **DAC+** (line-out) | Line-level source → external amp — HiFiBerry OS NG | **Ethernet** `192.168.178.244` (radios off) |

Both run Debian 13 (trixie). HifiBerry carries the HiFiBerry stack (PipeWire/WirePlumber,
AudioControl, Vue WebUI behind nginx, LADSPA Speaker EQ); Ampberry carries only shairport-sync +
nqptp, a Ruby tool set and a minimal Rails UI, all declared in the flake and applied with
system-manager. The per-device docs are the source of truth for hardware, software versions,
services/ports, key paths, the signal/gain chain, and device-specific gotchas.

## How to use this repo (for an AI assistant)

> Operating rules live in [`AGENTS.md`](./AGENTS.md) — read it first, then the relevant device doc.

1. **Read the device's `.md` first.** It lists the SSH target, the audio chain, how changes are
   made (HifiBerry: config + `systemctl --user`; Ampberry: the flake + `system-manager`), and known
   gotchas (Ampberry's `volume_max_db` ceiling; HifiBerry's Ethernet-only / radios-off setup).
2. **Honour the per-device "Agent guidelines"** — the Do / Ask-first / Never lists. These are live
   appliances; prefer config edits + service restarts over reboots, and treat audio-stack/kernel
   upgrades as manual, listen-tested steps.
3. **Keep the docs in sync.** When you change a machine's state (config, services, policy), update
   that device's `.md` in the same session so context never drifts from reality.

## Current state (snapshot)

- **Audio:** HifiBerry at unity gain end-to-end. Ampberry (2026-10-08) rebuilt as an AirPlay-2-only
  appliance with a `volume_max_db` ceiling (−6 dB) because full scale overdrives the Amp2 — see its
  "Volume ceiling" note.
- **Updates:** `unattended-upgrades` enabled on both — **Debian security only**, auto-reboot 04:00.
  HiFiBerry-repo and Raspberry Pi kernel/firmware updates stay manual; Ampberry's stack moves with
  `flake.lock`.
- **Access:** `pi` with passwordless sudo on both, SSH keys only (Ampberry: `PermitRootLogin no`,
  `AllowUsers pi`, nftables LAN-only firewall).
- **HifiBerry** is intentionally **Ethernet-only** (Wi‑Fi + Bluetooth radios disabled in `config.txt`).

## Conventions

- `aarch64 / arm64` only — never assume x86 binaries.
- Secrets (MPD/Spotify/Last.fm keys, SSH keys, Wi‑Fi/hotspot PSKs, password hashes) are **never**
  committed or logged; Ampberry's live only in gitignored `ampberry-v2/secrets.env` / `build/`.
- Ampberry is deployed only through Nix (`system-manager … --target-host`); never rsync.
- Each device doc ends with open questions / TBDs (e.g. speaker + amp details to fill in).
