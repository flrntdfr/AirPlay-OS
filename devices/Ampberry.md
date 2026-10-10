# Ampberry

AirPlay 2 speaker: Raspberry Pi 3B + HiFiBerry Amp2 driving a custom passive speaker pair.
Runs **AirPlay OS** (this repo) since 2026-10-08, migrated in place from HiFiBerry OS NG —
see [`OPERATIONS.md`](../OPERATIONS.md). Definition: [`ampberry.json`](./ampberry.json).

```
ssh pi@ampberry.local        # keys only, no passwords, no root login
ssh pi@192.168.178.221       # Wi‑Fi
http://ampberry.local/       # web UI: live log + player · Settings pane
```

## Installation

| | |
|---|---|
| Device id | `ampberry` (`systemConfigs.ampberry`) |
| Board | Raspberry Pi 3 Model B Rev 1.2 — aarch64, ~905 MB RAM, zram swap, 58 GB SD |
| HAT | HiFiBerry Amp2 (`dtoverlay=hifiberry-dacplus-std`), ALSA `hw:0`, mixer `Digital` |
| Speakers | custom passive pair (driver / enclosure / crossover: to be documented) |
| Network | Wi‑Fi `wlan0` on `192.168.178.0/24`, DHCP lease `192.168.178.221`; `eth0` as rescue path; onboarding hotspot `Ampberry-setup` (10.42.0.0/24) when no network; Bluetooth off |
| Users | `pi` (sudo, SSH keys); `ampberry` + `shairport-sync` system users (nologin, no sudo) |
| Base OS | Raspberry Pi OS Lite — Debian 13 (trixie), kernel `6.18.50+rpt-rpi-v8`, `raspi-firmware` 1.20260915 (apt; Debian security auto-updates only) |
| Nix | Determinate Nix 3.23.1 (multi-user), `trusted-users = root pi` |

## Versions (what is running)

| | | since |
|---|---|---|
| AirPlay OS | **build 34** · `95d580f`¹ · tag `v34` | 2026-10-10 |
| shairport-sync | 5.5.2 (AirPlay 2, ALSA, soxr, Avahi, metadata pipe) | 2026-10-08 |
| nqptp | 1.2.8 | 2026-10-08 |
| nixpkgs | 26.05 `7c8764b` · unstable `e7439b6` (audio only) · system-manager release-26.05 `8c7a4b8` | 2026-10-08 |
| Settings | `volume_max_db` **−6 dB** (listen-tested ceiling, the Amp2 clips and shuts down above it), interpolation auto, S32_LE, name "Ampberry", no password | 2026-10-08 |

¹ the exact flake revision is in `/etc/ampberry/release` on the box (`FLAKE_VERSION`), and in the
Settings pane's footer; the log of each deploy is in `OPERATIONS.md`.

## Notes specific to this unit

- **Volume ceiling.** Full-scale output overdrives the Amp2 (distorts, then shuts down): no
  software bug, just headroom. `volume_max_db` = −6 dB scales the phone's volume into
  `[−60, −6] dB` on the `Digital` mixer. Listen-test before raising it.
- **Pi 3 limits.** ~1 GB RAM, slow SD: the on-device shairport-sync update (Settings → Update now)
  compiles on the Pi and takes ~10 min; the Nix store grew to 3.2 GB after one — `sudo
  nix-collect-garbage` reclaims it.
- **Deploy** (from the Mac, repo root, clean checkout):
  `nix run github:numtide/system-manager/release-26.05 -- switch --flake .#ampberry --target-host pi@ampberry.local --sudo`
  then `tools/verify.sh`.

## Open

- Speaker/driver details above.
- A branded image on a spare SD card as cold standby (`tools/build-image.sh` → `tools/flash.sh`).
