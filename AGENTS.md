# AGENTS.md

Guidance for an AI assistant operating this repo. See [`README.md`](./README.md) for the full
framing — this repo is **Infrastructure as Context** for two Raspberry Pi audio appliances, not
deployment automation.

## Start here

1. Identify which device the task concerns and **read its doc first** — it is the source of truth:
   - [`Ampberry.md`](./Ampberry.md) — Pi 3B + DAC+/**Amp2**, powered speaker, Wi‑Fi `192.168.178.221`
   - [`HifiBerry.md`](./HifiBerry.md) — Pi 4B + **DAC+** line-out, Ethernet-only `192.168.178.244`
2. Connect over SSH as `pi` (key-based, passwordless sudo on both):
   `ssh pi@Ampberry.local` · `ssh pi@HifiBerry.local`
3. Follow that device's **Agent guidelines** section (Do / Ask-first / Never).

## Operating rules

- **Live appliances.** People listen to these. Prefer editing config under `/etc/` or
  `/home/pi/.state/` and restarting the specific service over rebooting.
- **Service split.** `systemctl --user` for PipeWire, WirePlumber, filter-chain, MPD, and players;
  `sudo systemctl` for `audiocontrol`, `nginx`, `config-server`, `sigmatcpserver`.
- **Verify audio for real** — `aplay -l`, `wpctl status`, `pw-link -l`, the WebUI/API, or a test
  tone — not just config syntax. Watch the full gain chain (PipeWire node volumes → Speaker EQ →
  ALSA `Digital`/`Analogue`); both devices are currently at clean unity gain.
- **Updates are split on purpose.** `unattended-upgrades` handles Debian **security** only
  (auto-reboot 04:00). HiFiBerry-stack and kernel/firmware upgrades are a **manual,
  listen-tested** `sudo apt upgrade` — never automate them.
- **arm64 only.** Never assume x86 binaries.
- **Never** commit or log secrets (MPD/Spotify/Last.fm keys, SSH keys), and don't re-enable
  HifiBerry's Wi‑Fi/Bluetooth radios without being asked — Ethernet-only is intentional.

## Keep context in sync

When you change a device's state (config, services, policy, volume chain), **update that device's
`.md` in the same session**, with a dated note for non-obvious decisions. The docs must never drift
from the running machines — that is the whole point of this repo.

## Ask first

Rebooting (interrupts playback/SSH), `apt upgrade` / package removal on the audio stack,
`/boot/firmware/config.txt` overlay changes, and disabling players that may be in active use.
