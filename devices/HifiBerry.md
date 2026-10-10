# HifiBerry

Line-level AirPlay source: Raspberry Pi 4B + HiFiBerry DAC+ (RCA line-out into an external
amplifier). Ethernet-only on purpose, both radios off. Definition for AirPlay OS:
[`hifiberry.json`](./hifiberry.json) (`systemConfigs.hifiberry`).

```
ssh pi@HifiBerry.local        # mDNS → Ethernet
ssh pi@192.168.178.244        # Ethernet (DHCP lease)
```

## Installation

| | |
|---|---|
| Device id | `hifiberry` |
| Board | Raspberry Pi 4 Model B Rev 1.2 — aarch64, ~1.8 GB RAM, 14 GB SD |
| HAT | HiFiBerry DAC+ (pcm512x, line-out, no amplifier) — `dtoverlay=hifiberry-dacplus-std` (what hbos wrote; the old note about EEPROM detection was wrong — checked 2026-10-10) |
| Network | Ethernet `eth0`, DHCP lease `192.168.178.244` (MAC `dc:a6:32:b3:8b:c8`); Wi‑Fi and Bluetooth **disabled** (`dtoverlay=disable-wifi`, `disable-bt`) |
| Downstream | external amplifier / powered speakers via RCA (gear: to be documented) |
| Users | `pi` (sudo, SSH keys) |

## Versions (what is running)

| | | since |
|---|---|---|
| OS | **HiFiBerry OS NG** `hbos-full` 0.11 on Raspberry Pi OS Lite (Debian 13, kernel `6.18.34+rpt-rpi-v8`) — PipeWire + WirePlumber, `hifiberry-audiocontrol` 0.8.3, `hifiberry-webui` 0.20.3, players MPD / Spotify Connect (librespot) / AirPlay (shairport) / Roon RAAT / squeezelite | 2026-06-26 (hbos 0.11 since 2026-07-24) |
| AirPlay OS | **not yet deployed** — see below | — |
| Volume chain | unity gain: PipeWire 1.0 → `speakereq2x2` flat → ALSA `Digital` 0 dB; the external amp sets the level | 2026-06-26 |

## Migration to AirPlay OS (pending)

The same in-place path Ampberry took on 2026-10-08 (`tools/apply-live.sh`, interactive, every
destructive step asks): backup off the device → stop and purge the hbos stack (all players,
PipeWire, the HiFiBerry repo) → install Nix → `system-manager switch --flake .#hifiberry` →
`ampberry provision` (config.txt: audio off, the `hifiberry-dacplus-std` overlay, I2C on, both
radios off) → reboot → `DEVICE=hifiberry tools/verify.sh` → listen-test.

What changes for this unit: AirPlay 2 only (no Spotify Connect, Roon, LMS, MPD, Bluetooth, no
PipeWire EQ); `volume_max_db` default **0 dB** (line-out at full scale, the amp has the knob);
no onboarding hotspot and no Wi‑Fi fallback timer (`"wifi": false`); the web UI's Network card
shows Wi‑Fi as absent. Run it as:

```bash
DEVICE=hifiberry AMPBERRY_HOST=pi@HifiBerry.local tools/apply-live.sh --harvest   # keys + hash into build/
DEVICE=hifiberry AMPBERRY_HOST=pi@HifiBerry.local tools/apply-live.sh             # the migration
```

Rollback: the backup tarball + `dpkg --get-selections` from step 1; hbos reinstalls with the
upstream two-liners (`hbosrepo`, `install-all`) and `hbos-full`.

## Until the migration: operating HiFiBerry OS NG

- `systemctl --user` for PipeWire, WirePlumber, `filter-chain`, MPD and the players;
  `sudo systemctl` for `audiocontrol`, `nginx`, `config-server`, `sigmatcpserver`.
- Web UI `http://HifiBerry.local/`; API `curl -s http://localhost/api/audiocontrol/players`.
- Config under `/etc/audiocontrol/`, `/etc/pipewire/pipewire.conf.d/` (`90-speakereq.conf` is the
  default sink), `/home/pi/.state/pipewire-api/settings.json`.
- `unattended-upgrades`: Debian security only (auto-reboot 04:00); the HiFiBerry apt repo
  (`/etc/apt/sources.list.d/hifiberry.list`) and kernel/firmware are manual, listen-tested upgrades.
- Bluetooth is off at every level (`disable-bt`, `bluetooth.service` disabled, `mpris-proxy` masked,
  `enable: false` in `audiocontrol.json`); the RIAA phono filter went with hbos 0.11.
- Test tone: a 2 s / 440 Hz / −12 dBFS WAV through `pw-play` reaches the line out cleanly (2026-06-26).

## Open

- External amplifier / speaker details.
- When to run the migration (it takes the box off the air for ~15 min and removes every non-AirPlay player).
