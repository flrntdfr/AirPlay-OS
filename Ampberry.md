# Ampberry

Powered speaker built on [HiFiBerry OS Next Generation (hbosng)](https://github.com/hifiberry/hifiberry-os/tree/hbosng). This Raspberry Pi runs Debian 13 with HiFiBerry packages on top of Raspberry Pi OS Lite. PipeWire routes multiple audio sources through DSP filter chains to a HiFiBerry DAC+/Amp2 HAT driving the speakers.

## Connect

```
ssh pi@Ampberry.local        # mDNS
ssh pi@192.168.178.221       # Wi‑Fi IP
```


## Hardware

| Component | Details |
|-----------|---------|
| Hostname | `Ampberry` (pretty + static) |
| Board | Raspberry Pi 3 Model B Rev 1.2 (aarch64, ~905 MB RAM) |
| HAT | HiFiBerry DAC+/Amp2 (`dtoverlay=hifiberry-dacplus-std`) |
| Speakers | Custom passive pair (driver/enclosure details — see below) |
| ALSA card | `hw:0` — `snd_rpi_hifiberry_dacplus` / pcm512x |
| Network | Wi‑Fi `wlan0` — `192.168.178.221/24` |
| Storage | 58 GB SD card (~8% used) |
| User | `pi` (passwordless sudo via `/etc/sudoers.d/010_pi-nopasswd`) |

## Software stack

| Layer | Version / package |
|-------|-------------------|
| OS | Debian GNU/Linux 13 (trixie) |
| Kernel | `6.18.33+rpt-rpi-v8` |
| HiFiBerry OS | `hbos-full` 0.9 |
| Audio daemon | PipeWire + WirePlumber (user services) |
| Control plane | `hifiberry-audiocontrol` 0.7.12 |
| Web UI | `hifiberry-webui` 0.19.11 via nginx |
| Config | `hifiberry-configurator` 2.13.14 |

**Primary use case:** streaming (Spotify Connect, AirPlay, Roon, LMS, Bluetooth).

Upstream docs: [hbosng README](https://github.com/hifiberry/hifiberry-os/blob/hbosng/README.md), [add your own player](https://github.com/hifiberry/hifiberry-os/blob/hbosng/docs/add-your-own-player.md).

## Architecture

```
Players (MPD, Spotify, AirPlay, RAAT, LMS, Bluetooth)
        ↓
   PipeWire / WirePlumber
        ↓
Filter chains: Speaker EQ 2x2 → RIAA Phono Preamp (optional)
        ↓
   HiFiBerry DAC+/Amp2 (hw:0)
        ↓
      Speakers
```

**AudioControl** is the central service. It manages player state, volume, metadata, and exposes a REST API. The **WebUI** is a Vue SPA served by nginx and talks to AudioControl and other backend APIs.

### Audio players (configured)

| Player | Package | Notes |
|--------|---------|-------|
| MPD | `hifiberry-mpd` | Local files, port 6600, user systemd unit |
| Spotify Connect | `hifiberry-librespot` | Managed by AudioControl |
| AirPlay | `hifiberry-shairport` | `shairport.service` (user) |
| Roon RAAT | `hifiberry-raat` | Pipes under `/var/lib/raat/` |
| Logitech Media Server | `hifiberry-squeezelite` | Auto-discovery enabled |
| Bluetooth | `hifiberry-bluetooth` | BlueZ / mpris-proxy |

### PipeWire filter chains

Two LADSPA filter chains are active in `/etc/pipewire/pipewire.conf.d/`:

- **`90-speakereq.conf`** — 2×2 stereo speaker EQ (`speakereq2x2.so`). Runtime settings in `/home/pi/.state/pipewire-api/settings.json`.
- **`90-riaa.conf`** — RIAA phono preamp (`riaa.so`) for vinyl input. Settings also in `settings.json` under the `riaa` key.

Headless PipeWire overrides disable X11/session-bus modules in `99-hifiberry-headless.conf`.

## Services and ports

### System services (`systemctl`)

| Service | Purpose |
|---------|---------|
| `audiocontrol.service` | Player management, metadata, built-in API |
| `config-server.service` | System/audio card configuration API |
| `nginx.service` | Web UI + API reverse proxy |
| `sigmatcpserver.service` | DSP TCP/REST API |

### User services (`systemctl --user`, run as `pi`)

| Service | Purpose |
|---------|---------|
| `pipewire.service` | Audio routing |
| `wireplumber.service` | Session manager |
| `pipewire-pulse.service` | PulseAudio compatibility |
| `filter-chain.service` | LADSPA filter chains |
| `pipewire-api.service` | PipeWire REST API |
| `mpd.service` | Music Player Daemon |
| `shairport.service` | AirPlay receiver |
| `vu-meter.service` | VU meter for WebUI |
| `mpris-proxy.service` | Bluetooth media control |

### HTTP endpoints (via nginx on port 80)

| URL prefix | Backend | Port |
|------------|---------|------|
| `/` | HiFiBerry WebUI | static |
| `/api/audiocontrol/` | AudioControl | 1080 |
| `/api/config/` | Config server | 1081 |
| `/api/pipewire/` | PipeWire API | 2716 |
| `/api/roomeq/` | Room EQ | 10315 |
| `/api/dsptoolkit/` | SigmaTCP DSP | 13141 |
| `/api/vu-meter/` | VU meter | 2717 |
| `/api/btaudio/` | Bluetooth audio | 1082 |

Web UI: `http://Ampberry/` or `http://192.168.178.221/` (mDNS: `Ampberry.local`)

## Key paths

| Path | Purpose |
|------|---------|
| `/etc/audiocontrol/` | AudioControl config (`audiocontrol.json`, player defs) |
| `/etc/pipewire/pipewire.conf.d/` | PipeWire overrides (EQ, RIAA, headless) |
| `/etc/nginx/` | Web UI and API proxy config |
| `/boot/firmware/config.txt` | Device tree overlays (HAT, I2C, audio off) |
| `/var/lib/audiocontrol/` | AudioControl cache and settings DB |
| `/var/lib/mpd/` | MPD music library and database |
| `/home/pi/.state/` | PipeWire API runtime state |
| `/home/pi/etc/` | Local config copies (e.g. `mpd.conf`) |
| `/home/pi/.raat/`, `.shairport/`, `.squeezelite/` | Player runtime dirs |

## Common commands

```bash
# Check player status
curl -s http://localhost/api/audiocontrol/players | python3 -m json.tool

# Restart audio after PipeWire config changes
systemctl --user restart pipewire wireplumber filter-chain

# Restart control plane after /etc/audiocontrol changes
sudo systemctl restart audiocontrol

# Restart web stack
sudo systemctl restart nginx

# List audio hardware
aplay -l
pw-cli info all | grep -E 'node.name|node.description'

# Inspect running user services
systemctl --user list-units --type=service --state=running

# Package info
dpkg -l | grep -i hifiberry
```

### Automatic updates (unattended-upgrades)

`unattended-upgrades` is enabled and restricted to **Debian security updates only**:

- Allowed origins: `Debian-Security` (`trixie-security`). The HiFiBerry repo
  (`debianrepo.hifiberry.com`) and Raspberry Pi kernel/firmware repo
  (`archive.raspberrypi.com`) are **excluded** — those are upgraded manually and listen-tested.
- Automatic **reboot at 04:00** when a security update requires it (briefly drops playback/SSH).
- Unused kernels and dependencies are auto-removed (SD-card hygiene).

Config: `/etc/apt/apt.conf.d/52unattended-upgrades-local` (policy) and
`/etc/apt/apt.conf.d/20auto-upgrades` (enables `apt-daily-upgrade.timer`).

Audio-stack and kernel upgrades remain a deliberate manual step from the HiFiBerry apt
repository (`/etc/apt/sources.list.d/hifiberry.list`):

```bash
sudo apt update && sudo apt upgrade   # review, then listen-test afterward
```

Initial install reference (already done on this device):

```bash
curl -Ls https://tinyurl.com/hbosrepo | bash
curl -Ls https://raw.githubusercontent.com/hifiberry/hifiberry-os/refs/heads/hbosng/install-all | bash
sudo apt install -y hbos-full
sudo config-configtxt --default-config --enable-i2c
```

## Agent guidelines

### Do

- Treat this as a **live audio appliance** on constrained hardware (Pi 3, ~1 GB RAM).
- Prefer editing config under `/etc/` or `/home/pi/.state/` and restarting the relevant service over rebooting.
- Use `systemctl --user` for PipeWire, MPD, and player services; use `sudo systemctl` for AudioControl, nginx, and config-server.
- Verify audio changes with `aplay -l`, `pw-cli`, or the WebUI/API — not just config syntax.
- Keep changes minimal and focused; match existing HiFiBerry conventions.

### Ask first

- Rebooting the device (interrupts playback and SSH).
- `apt upgrade` / package removals (may break the audio stack).
- Changes to `/boot/firmware/config.txt` device-tree overlays.
- Disabling or removing players that may be in active use.

### Never

- Commit or log secrets (MPD passwords, Spotify/Last.fm API keys, SSH keys).
- Force-push or rewrite git history unless explicitly asked.
- Run destructive commands (`rm -rf`, `mkfs`, `dd`) without explicit confirmation.
- Assume x86 binaries — this is **aarch64 / arm64**.

## Project layout (this workspace)

```
/home/pi/
├── AGENTS.md          # This file
├── etc/               # Local config staging (mpd.conf)
├── .state/            # PipeWire API runtime settings
├── .raat/             # RAAT player config
├── .shairport/        # Shairport config
└── .squeezelite/      # Squeezelite config
```

Most HiFiBerry software is installed as Debian packages under `/usr/` and `/etc/`. Custom development, if any, should live under `/home/pi/`.

## Speaker build (custom passive)

The Amp2 HAT drives a custom passive speaker pair. Document driver model, enclosure, crossover, and any EQ tuning notes here once known:

```
Driver(s):
Enclosure:
Crossover:
EQ notes:
```

The **Speaker EQ 2x2** PipeWire filter (`90-speakereq.conf`) is the right place to tune frequency response. Settings persist in `/home/pi/.state/pipewire-api/settings.json` and are exposed via `/api/pipewire/`.

The **RIAA phono preamp** filter is installed but secondary for the streaming-focused setup. It can stay disabled unless vinyl input is added later.

### Volume / loudness gotcha (diagnosed 2026-06-26)

Sound was quieter than on the old (pre-PipeWire) OS. Cause: the DAC output node
(`alsa_output.platform-soc_sound.stereo-fallback`, shown as "Built-in Audio Stereo")
carried a persisted PipeWire **software** volume of cubic 0.40 ≈ linear 0.064 (**−24 dB**),
applied as `softVolumes`. The WebUI/AudioControl slider drives a *different* control — the
ALSA **`Digital`** mixer (auto-detected, `services.volume.type = alsa`) — so this hidden cut
was unreachable from the UI and stacked on top of every source.

Fix — restore the output node to unity (0 dB); WirePlumber persists it in
`~/.local/state/wireplumber/default-routes`:

```bash
# node id from: wpctl status   (the "Built-in Audio Stereo" sink)
wpctl set-volume <id> 1.0
wpctl get-volume <id>          # -> Volume: 1.00
```

The signal chain is now unity throughout (DAC node 0 dB → flat Speaker EQ → `Digital` mixer
governs level). **Max output is ~24 dB louder than before the fix** — start the WebUI slider
low and ramp up. Unity is the clean maximum; going beyond it (extra gain in the EQ
`master_gain_db`) risks digital clipping. RIAA is *not* in the streaming path (default sink is
`speakereq2x2`; the `riaa` node feeds in but has no source).

## Open questions

- Custom code / automation plans under `/home/pi/` (TBD)
- Git workflow for any custom scripts or configs
