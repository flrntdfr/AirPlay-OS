# HifiBerry

Line-level streaming source built on [HiFiBerry OS Next Generation (hbosng)](https://github.com/hifiberry/hifiberry-os/tree/hbosng). This Raspberry Pi runs Debian 13 with HiFiBerry packages on top of Raspberry Pi OS Lite. PipeWire routes multiple audio sources through DSP filter chains to a HiFiBerry **DAC+** HAT, whose RCA line output feeds an external amplifier / powered speakers.

> Sibling device: [`Ampberry.md`](./Ampberry.md) — a Pi 3 + DAC+/**Amp2** powered speaker. Same software stack; the main differences here are **Pi 4**, a **DAC+ (line-out, no built-in amp)**, **Ethernet-only** (Wi‑Fi and Bluetooth radios disabled), and HAT detection via **EEPROM auto-read** rather than an explicit overlay.

## Connect

```
ssh pi@HifiBerry.local        # mDNS → Ethernet
ssh pi@192.168.178.244        # Ethernet IP (DHCP)
```

## Hardware

| Component | Details |
|-----------|---------|
| Hostname | `HifiBerry` (static) |
| Board | Raspberry Pi 4 Model B Rev 1.2 (aarch64, ~1.8 GB RAM) |
| HAT | HiFiBerry **DAC+** (line-out, pcm512x) — auto-detected via HAT EEPROM |
| Output | RCA line-level → external amp / powered speakers (no onboard amplifier) |
| ALSA card | `hw:0` — `snd_rpi_hifiberry_dacplus` / pcm512x |
| Network | **Ethernet `eth0`** — `192.168.178.244/24` (MAC `dc:a6:32:b3:8b:c8`) |
| Radios | Wi‑Fi + Bluetooth **disabled** (see config.txt overlays) |
| Storage | 14 GB SD card (~38% used) |
| User | `pi` (passwordless sudo) |

## Software stack

| Layer | Version / package |
|-------|-------------------|
| OS | Debian GNU/Linux 13 (trixie) |
| Kernel | `6.18.34+rpt-rpi-v8` |
| HiFiBerry OS | `hbos-full` 0.9 |
| Audio daemon | PipeWire + WirePlumber (user services) |
| Control plane | `hifiberry-audiocontrol` 0.7.13 |
| Web UI | `hifiberry-webui` 0.19.11 via nginx |
| Config | `hifiberry-configurator` 2.13.16 |

**Primary use case:** streaming (Spotify Connect, AirPlay, Roon, LMS). Bluetooth is disabled on this unit.

Upstream docs: [hbosng README](https://github.com/hifiberry/hifiberry-os/blob/hbosng/README.md), [add your own player](https://github.com/hifiberry/hifiberry-os/blob/hbosng/docs/add-your-own-player.md).

## Architecture

```
Players (MPD, Spotify, AirPlay, RAAT, LMS)
        ↓
   PipeWire / WirePlumber
        ↓
Filter chains: Speaker EQ 2x2 → RIAA Phono Preamp (optional)
        ↓
   HiFiBerry DAC+ (hw:0)  →  RCA line out
        ↓
   External amplifier / powered speakers
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
| ~~Bluetooth~~ | `hifiberry-bluetooth` | **Disabled** — radio off, services off, `enable: false` in audiocontrol.json |

### PipeWire filter chains

Two LADSPA filter chains are active in `/etc/pipewire/pipewire.conf.d/`:

- **`90-speakereq.conf`** — 2×2 stereo speaker EQ (`speakereq2x2.so`). This is the **default sink**. Runtime settings in `/home/pi/.state/pipewire-api/settings.json`.
- **`90-riaa.conf`** — RIAA phono preamp (`riaa.so`) for vinyl input. Settings also in `settings.json` under the `riaa` key. **Not** in the streaming path (it has no source feeding it).

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
| `librespot.service` | Spotify Connect |
| `raat.service` | Roon RAAT |
| `squeezelite.service` | LMS player |
| `vu-meter.service` | VU meter for WebUI |
| ~~`mpris-proxy.service`~~ | Bluetooth media control — **masked** (BT disabled) |

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
| `/api/btaudio/` | Bluetooth audio | 1082 (BT disabled) |

Web UI: `http://HifiBerry/` or `http://192.168.178.244/` (mDNS: `HifiBerry.local`)

## Key paths

| Path | Purpose |
|------|---------|
| `/etc/audiocontrol/` | AudioControl config (`audiocontrol.json`, `players.d/`) |
| `/etc/pipewire/pipewire.conf.d/` | PipeWire overrides (EQ, RIAA, headless) |
| `/etc/nginx/` | Web UI and API proxy config |
| `/boot/firmware/config.txt` | Device tree overlays (HAT EEPROM read, I2C, audio off, radios off) |
| `/var/lib/audiocontrol/` | AudioControl cache and settings DB |
| `/var/lib/mpd/` | MPD music library and database |
| `/home/pi/.state/pipewire-api/settings.json` | PipeWire filter (EQ/RIAA) runtime state |
| `/home/pi/.local/state/wireplumber/` | WirePlumber persisted device/stream volumes |

## Common commands

```bash
# Check player status
curl -s http://localhost/api/audiocontrol/players | python3 -m json.tool

# Restart audio after PipeWire config changes
systemctl --user restart pipewire wireplumber filter-chain

# Restart control plane after /etc/audiocontrol changes
sudo systemctl restart audiocontrol

# List audio hardware
aplay -l
wpctl status

# Play a test tone to the line out (moderate level)
pw-play /tmp/tone.wav   # generated by the snippet under "Sound check"

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

## Install reference (performed on this device, 2026-06-26)

Starting from a fresh Raspberry Pi OS Lite (Debian 13) install:

```bash
# 1. Add the HiFiBerry apt repo + signing key (equivalent of the addrepo script)
. /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/hifiberry-archive-keyring.gpg] http://debianrepo.hifiberry.com $VERSION_CODENAME main" \
  | sudo tee /etc/apt/sources.list.d/hifiberry.list
wget -qO- "https://keys.openpgp.org/vks/v1/by-fingerprint/4192E989F186E770B273F98B7997FC464E443CFA" \
  | gpg --dearmor | sudo tee /usr/share/keyrings/hifiberry-archive-keyring.gpg >/dev/null
sudo apt update

# 2. Core packages + config (equivalent of install-all)
sudo apt install -y hbos-minimal
sudo config-configtxt --default-config --enable-i2c   # onboard+HDMI audio off, I2C/SPI on, EEPROM read on
echo "$USER" | sudo tee /etc/hifiberry.user
sudo loginctl enable-linger "$USER"                    # user services start at boot

# 3. Full stack (all players, RoomEQ, etc.)
sudo apt install -y hbos-full

# 4. Reboot to load the HAT overlay (EEPROM auto-detect) and apply config
sudo reboot
```

> The upstream one-liners are `curl -Ls https://tinyurl.com/hbosrepo | bash` and
> `curl -Ls https://raw.githubusercontent.com/hifiberry/hifiberry-os/refs/heads/hbosng/install-all | bash`.
> The steps above are the inspected, non-piped equivalents.

## Appliance customizations (this unit)

This device is wired via **Ethernet only**; both onboard radios are disabled and Bluetooth playback is off.

`/boot/firmware/config.txt` tail:

```ini
# Appliance: disable onboard radios (Ethernet-only)
dtoverlay=disable-bt
dtoverlay=disable-wifi
```

Bluetooth was also disabled at the service/config level (mirrors Ampberry):

```bash
# audiocontrol.json: bluetooth player "enable": false
sudo systemctl disable --now bluetooth.service hifiberry-bluetooth.service
systemctl --user mask mpris-proxy.service     # BT MPRIS bridge — kept off
```

To re-enable Wi‑Fi or Bluetooth later: remove the matching `dtoverlay=disable-*` line from
`config.txt`, reboot, then re-enable the services (and unmask `mpris-proxy` / set the audiocontrol
bluetooth player back to `enable: true`).

## Sound check (verified 2026-06-26)

The full chain is at **unity gain** out of the box — unlike Ampberry, this fresh install did **not**
carry a hidden PipeWire software attenuation:

- DAC output node `alsa_output.platform-soc_sound.stereo-fallback` → `channelVolumes [1.0, 1.0]`
- `speakereq2x2` sink → `[1.0, 1.0]`, EQ bands all flat
- ALSA `Digital` mixer → 207/207 = **0 dB** (this is what the WebUI/AudioControl slider drives)
- Default sink = `speakereq2x2`; RIAA not in the streaming path

> Worth knowing (see Ampberry's "Volume / loudness gotcha"): WirePlumber persists a per-device
> software volume in `~/.local/state/wireplumber/default-routes` that is *separate* from the
> WebUI's ALSA `Digital` control. If output ever becomes quiet with the slider already high,
> check it with `wpctl status` (the "Built-in Audio Stereo" sink) and restore unity:
> `wpctl set-volume <id> 1.0`.

A 2 s / 440 Hz / −12 dBFS test tone played cleanly through to the line out. Because the DAC+ has
**no onboard amplifier**, audio is only audible when an amp or powered speakers are connected to the
RCA jacks. Generate and play the tone with:

```bash
python3 - <<'EOF'
import struct,math,wave
sr=48000; dur=2.0; f=440.0; amp=0.25  # -12 dBFS
w=wave.open("/tmp/tone.wav","w"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
N=int(sr*dur)
for n in range(N):
    env=min(1.0, n/(sr*0.05), (N-n)/(sr*0.05))
    s=int(amp*env*math.sin(2*math.pi*f*n/sr)*32767)
    w.writeframesraw(struct.pack("<hh",s,s))
w.close()
EOF
pw-play /tmp/tone.wav
```

## Agent guidelines

### Do

- Treat this as a **live audio appliance**; it is the line-level source for an external amp.
- Prefer editing config under `/etc/` or `/home/pi/.state/` and restarting the relevant service over rebooting.
- Use `systemctl --user` for PipeWire, MPD, and player services; use `sudo systemctl` for AudioControl, nginx, and config-server.
- Verify audio changes with `aplay -l`, `wpctl`, or the WebUI/API — not just config syntax.
- Keep changes minimal and focused; match existing HiFiBerry conventions.
- Reach this device over **Ethernet** (`HifiBerry.local` / `192.168.178.244`); Wi‑Fi is off.

### Ask first

- Rebooting the device (interrupts playback and SSH).
- `apt upgrade` / package removals (may break the audio stack).
- Changes to `/boot/firmware/config.txt` device-tree overlays (incl. re-enabling radios).
- Disabling or removing players that may be in active use.

### Never

- Commit or log secrets (MPD passwords, Spotify/Last.fm API keys, SSH keys).
- Re-enable Wi‑Fi/Bluetooth without being asked — this unit is intentionally Ethernet-only.
- Run destructive commands (`rm -rf`, `mkfs`, `dd`) without explicit confirmation.
- Assume x86 binaries — this is **aarch64 / arm64**.

## Output chain (external amp + speakers)

The DAC+ feeds an external amplifier via RCA. Document the downstream gear and any EQ tuning here once known:

```
Amplifier:
Speakers:
Cabling:
EQ notes:
```

The **Speaker EQ 2x2** PipeWire filter (`90-speakereq.conf`) is the right place to tune frequency
response. Settings persist in `/home/pi/.state/pipewire-api/settings.json` and are exposed via
`/api/pipewire/`. The **RIAA phono preamp** filter is installed but secondary; leave it disabled
unless vinyl input is added later.

## Open questions

- External amplifier / speaker details (TBD — fill in above).
- Custom code / automation plans under `/home/pi/` (TBD).
