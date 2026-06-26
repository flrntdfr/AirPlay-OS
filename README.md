# HiFiBerry — Infrastructure as Context

This repository is the **Infrastructure as Context** for two Raspberry Pi audio appliances
running [HiFiBerry OS Next Generation (hbosng)](https://github.com/hifiberry/hifiberry-os/tree/hbosng).

It is not deployment automation. It is a curated, human- and agent-readable description of
**what these machines are, how they're wired, and the decisions behind their current state** —
the context an AI assistant (or a future me) needs to operate them safely without re-discovering
everything from scratch each time.

## Devices

| Device | Doc | Board + HAT | Role | Network |
|--------|-----|-------------|------|---------|
| **Ampberry** | [`Ampberry.md`](./Ampberry.md) | Pi 3B + DAC+/**Amp2** | Powered speaker (built-in amp → passive speakers) | Wi‑Fi `192.168.178.221` |
| **HifiBerry** | [`HifiBerry.md`](./HifiBerry.md) | Pi 4B + **DAC+** (line-out) | Line-level source → external amp | **Ethernet** `192.168.178.244` (radios off) |

Both run Debian 13 (trixie) + the HiFiBerry stack: PipeWire/WirePlumber, AudioControl, a Vue WebUI
behind nginx, and LADSPA filter chains (Speaker EQ + optional RIAA). The per-device docs are the
source of truth for hardware, software versions, services/ports, key paths, the signal/gain chain,
and device-specific gotchas.

## How to use this repo (for an AI assistant)

> Operating rules live in [`AGENTS.md`](./AGENTS.md) — read it first, then the relevant device doc.

1. **Read the device's `.md` first.** It lists the SSH target, the audio chain, the
   services-vs-`systemctl --user` split, and known gotchas (e.g. Ampberry's hidden PipeWire volume
   attenuation; HifiBerry's Ethernet-only / radios-off setup).
2. **Honour the per-device "Agent guidelines"** — the Do / Ask-first / Never lists. These are live
   appliances; prefer config edits + service restarts over reboots, and treat audio-stack/kernel
   upgrades as manual, listen-tested steps.
3. **Keep the docs in sync.** When you change a machine's state (config, services, policy), update
   that device's `.md` in the same session so context never drifts from reality.

## Current state (snapshot)

- **Audio:** both verified at unity gain end-to-end (clean maximum output). Ampberry's −24 dB
  PipeWire software cut was found and fixed; see its "Volume / loudness gotcha" note.
- **Updates:** `unattended-upgrades` enabled on both — **Debian security only**, auto-reboot 04:00.
  HiFiBerry-repo and Raspberry Pi kernel/firmware updates stay manual.
- **Access:** `pi` with passwordless sudo on both. SSH key-based.
- **HifiBerry** is intentionally **Ethernet-only** (Wi‑Fi + Bluetooth radios disabled in `config.txt`).

## Conventions

- `aarch64 / arm64` only — never assume x86 binaries.
- Secrets (MPD/Spotify/Last.fm keys, SSH keys) are **never** committed or logged.
- Each device doc ends with open questions / TBDs (e.g. speaker + amp details to fill in).
