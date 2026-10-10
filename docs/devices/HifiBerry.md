# HifiBerry

Line-level AirPlay 2 source: Raspberry Pi 4B + HiFiBerry DAC+ (RCA line-out into an external
amplifier). Ethernet-only on purpose, both radios off. Runs **AirPlay OS** (this repo) since
2026-10-10, migrated in place from HiFiBerry OS NG — see [`OPERATIONS.md`](../OPERATIONS.md).
Definition: [`hifiberry.json`](./hifiberry.json) (`systemConfigs.hifiberry`).

```
ssh pi@HifiBerry.local        # keys only, no passwords, no root login — Ethernet
ssh pi@192.168.178.244        # DHCP lease
http://HifiBerry.local/       # web UI: live log + player · Settings pane
```

## Installation

| | |
|---|---|
| Device id | `hifiberry` |
| Board | Raspberry Pi 4 Model B Rev 1.2 — aarch64, ~1.8 GB RAM, 14 GB SD (42 % used) |
| HAT | HiFiBerry DAC+ (pcm512x, line-out, no amplifier) — `dtoverlay=hifiberry-dacplus-std` (what hbos had written; the old note about EEPROM detection was wrong — checked 2026-10-10), ALSA `hw:0` |
| Network | Ethernet `eth0`, DHCP lease `192.168.178.244` (MAC `dc:a6:32:b3:8b:c8`); Wi‑Fi and Bluetooth **disabled** (`dtoverlay=disable-wifi`, `disable-bt`); no onboarding hotspot, no Wi‑Fi fallback timer |
| Hostname | `HifiBerry` (static, kept from hbos; the cloud-init seed would set `hifiberry` on a Clean reboot — same mDNS name) |
| Downstream | external amplifier / powered speakers via RCA (gear: to be documented) |
| Users | `pi` (sudo, SSH keys); `airplay-os` + `shairport-sync` system users (nologin, no sudo) |
| Base OS | Raspberry Pi OS Lite — Debian 13 (trixie), kernel `6.18.34+rpt-rpi-v8` (apt; Debian security auto-updates only; a kernel upgrade is pending — manual, listen-tested) |
| Nix | Determinate Nix (multi-user), `trusted-users = root pi`, store 0.9 GB |

## Versions (what is running)

| | | since |
|---|---|---|
| AirPlay OS | **build 40** · `2145e7f`¹ (old count, migrated at build 38 `ce6c9b7`; counting restarted with `START` = v1 on 2026-10-10) | 2026-10-10 |
| shairport-sync | 5.5.2 (AirPlay 2, ALSA, soxr, Avahi, metadata pipe) | 2026-10-10 |
| nqptp | 1.2.8 | 2026-10-10 |
| nixpkgs | 26.05 `7c8764b` · unstable `e7439b6` (audio only) · system-manager release-26.05 `8c7a4b8` | 2026-10-10 |
| Settings | name "HifiBerry", no password, interpolation auto, S32_LE, `volume_max_db` **0 dB** (line-out at full scale — the amplifier has the knob), range 60 dB | 2026-10-10 |

¹ `/etc/airplay-os/release` on the box (`FLAKE_VERSION`), also in the Settings pane's footer.

Before 2026-10-10: HiFiBerry OS NG `hbos-full` 0.11 (installed 2026-06-26, 0.11 since
2026-07-24) — PipeWire + WirePlumber, AudioControl, players MPD / Spotify Connect / AirPlay /
Roon RAAT / squeezelite, speaker-EQ filter chain. All of it purged by the migration; the backup
(`/etc`, `/home/pi/.state`, dpkg selections) is in the Mac's `build/backup-pre-nix-20261010-172250.tgz`.

## Notes specific to this unit

- **Volume.** The DAC+ output is line level; `volume_max_db` 0 dB maps the phone's slider onto
  `[−60, 0] dB` of the `Digital` mixer. Not yet listen-tested with the amplifier after the migration.
- **Ethernet only.** `docs/devices/hifiberry.json` has `"wifi": false`: no hotspot, no Wi‑Fi timer, no
  hotspot firewall rules, `disable-wifi` in config.txt. The Settings pane's Network card shows
  Wi‑Fi as absent; the Ethernet switch stays locked (it is the only way in).
- **Rollback** (if ever): the backup tarball + `dpkg-selections-20261010-172250.txt` in `build/`,
  then the hbos upstream two-liners (`hbosrepo`, `install-all`) and `hbos-full`.
- **Deploy** (from the Mac, repo root, clean checkout):
  `nix run github:numtide/system-manager/release-26.05 -- switch --flake .#hifiberry --target-host pi@HifiBerry.local --sudo`
  then `DEVICE=hifiberry tools/verify.sh`.

## Open

- External amplifier / speaker details; a listen-test of the migrated box.
- Kernel/firmware upgrade (`6.18.34` → current) — manual `sudo apt upgrade`, listen-tested.
